-- =====================================================================
-- 07_pkg_notifications.sql
-- Package de notifications email pour alertes et événements
-- =====================================================================

ALTER SESSION SET CURRENT_SCHEMA = ERP_APP;

-- Pré-requis : configurer SMTP au niveau base
-- BEGIN
--   DBMS_SCHEDULER.SET_AGENT_ATTRIBUTES(
--       'email_address', 'smtp.example.com:587',
--       'email_username', 'noreply@retailchain.com',
--       'email_password', '***',
--       'email_use_ssl', 'Y');
-- END;
-- /

CREATE OR REPLACE PACKAGE pkg_notifications AS

    -- Envoyer une alerte stock bas
    PROCEDURE notify_low_stock(
        p_site_code IN VARCHAR2,
        p_codart    IN VARCHAR2,
        p_qte_phy   IN NUMBER,
        p_qte_min   IN NUMBER
    );

    -- Envoyer une notification de transfert en transit
    PROCEDURE notify_transfer_shipped(
        p_transfer_num IN VARCHAR2,
        p_dest_site    IN VARCHAR2,
        p_priority     IN VARCHAR2
    );

    -- Notifier HQ d'un transfert réceptionné
    PROCEDURE notify_transfer_received(
        p_transfer_num  IN VARCHAR2,
        p_dest_site     IN VARCHAR2,
        p_reception_par IN VARCHAR2,
        p_etat          IN VARCHAR2
    );

    -- Job : notifier quotidiennement les ruptures
    PROCEDURE job_daily_low_stock_alerts;

END pkg_notifications;
/

CREATE OR REPLACE PACKAGE BODY pkg_notifications AS

    PROCEDURE notify_low_stock(
        p_site_code IN VARCHAR2,
        p_codart    IN VARCHAR2,
        p_qte_phy   IN NUMBER,
        p_qte_min   IN NUMBER
    ) IS
        v_subject VARCHAR2(200);
        v_body    VARCHAR2(4000);
        v_to      VARCHAR2(200);
    BEGIN
        -- Récupérer le mail du manager du site
        SELECT MAX(EMAIL) INTO v_to
          FROM "TES-USER" u
          JOIN "TES-SITE" s ON s.ID = u.SITE_ID
         WHERE s.SITE_CODE = p_site_code;

        IF v_to IS NULL THEN
            DBMS_OUTPUT.PUT_LINE('Pas de destinataire pour ' || p_site_code);
            RETURN;
        END IF;

        v_subject := '[ALERTE] ' || p_site_code || ' : Stock bas pour ' || p_codart;
        v_body := 'Bonjour,<br><br>'
                || 'Le stock de l''article <b>' || p_codart || '</b> sur le site <b>' || p_site_code || '</b> '
                || 'est de <b>' || p_qte_phy || '</b> (minimum : ' || p_qte_min || ').<br><br>'
                || 'Merci de lancer un réapprovisionnement.<br><br>'
                || 'Cordialement,<br>Système ERP';

        -- Envoi via UTL_SMTP (Oracle 21c inclut UTL_MAIL)
        DECLARE
            v_mailhost VARCHAR2(100) := 'localhost';
            v_from     VARCHAR2(100) := 'noreply@retailchain.com';
        BEGIN
            UTL_MAIL.SEND(
                sender     => v_from,
                recipients => v_to,
                subject    => v_subject,
                message    => v_body,
                mime_type  => 'text/html; charset=utf-8'
            );
        EXCEPTION
            WHEN OTHERS THEN
                -- Log dans audit en cas d'échec
                INSERT INTO "TES-SITE-AUDIT" (SITE_ID, AUDIT_TYPE, ACTION, USER_NAME, DETAILS)
                VALUES ((SELECT ID FROM "TES-SITE" WHERE SITE_CODE=p_site_code),
                        'NOTIFICATION_FAILED', 'EMAIL_SEND', USER, SQLERRM);
                COMMIT;
        END;

        INSERT INTO "TES-SITE-AUDIT" (SITE_ID, AUDIT_TYPE, ACTION, USER_NAME, DETAILS)
        VALUES ((SELECT ID FROM "TES-SITE" WHERE SITE_CODE=p_site_code),
                'NOTIFICATION_SENT', 'EMAIL_SEND', USER,
                'Article ' || p_codart || ' : ' || p_qte_phy || ' (min=' || p_qte_min || ')');
        COMMIT;
    END;

    PROCEDURE notify_transfer_shipped(
        p_transfer_num IN VARCHAR2,
        p_dest_site    IN VARCHAR2,
        p_priority     IN VARCHAR2
    ) IS
        v_subject VARCHAR2(200);
        v_body    VARCHAR2(4000);
        v_to      VARCHAR2(200);
    BEGIN
        SELECT MAX(EMAIL) INTO v_to
          FROM "TES-USER" u
          JOIN "TES-SITE" s ON s.ID = u.SITE_ID
         WHERE s.SITE_CODE = p_dest_site;

        IF v_to IS NULL THEN RETURN; END IF;

        v_subject := '[TRANSFERT] ' || p_transfer_num || ' expédié vers ' || p_dest_site;
        v_body := 'Le transfert <b>' || p_transfer_num || '</b> (' || p_priority || ') '
                || 'a été expédié vers votre site <b>' || p_dest_site || '</b>.<br>'
                || 'Préparez la réception dès que possible.';

        BEGIN
            UTL_MAIL.SEND(
                sender     => 'noreply@retailchain.com',
                recipients => v_to,
                subject    => v_subject,
                message    => v_body,
                mime_type  => 'text/html; charset=utf-8'
            );
        EXCEPTION
            WHEN OTHERS THEN
                INSERT INTO "TES-SITE-AUDIT" (SITE_ID, AUDIT_TYPE, ACTION, USER_NAME, DETAILS)
                VALUES ((SELECT ID FROM "TES-SITE" WHERE SITE_CODE=p_dest_site),
                        'NOTIFICATION_FAILED', 'EMAIL_SEND', USER, SQLERRM);
                COMMIT;
        END;
        COMMIT;
    END;

    PROCEDURE notify_transfer_received(
        p_transfer_num  IN VARCHAR2,
        p_dest_site     IN VARCHAR2,
        p_reception_par IN VARCHAR2,
        p_etat          IN VARCHAR2
    ) IS
        v_subject VARCHAR2(200);
        v_to      VARCHAR2(200);
    BEGIN
        -- Email au HQ
        SELECT MAX(EMAIL) INTO v_to
          FROM "TES-USER" u
          JOIN "TES-SITE" s ON s.ID = u.SITE_ID
         WHERE s.SITE_CODE = 'HQ' AND u.USER_ROLE = 'HQ_ADMIN';

        IF v_to IS NULL THEN RETURN; END IF;

        v_subject := '[HQ] Réception ' || p_transfer_num || ' : ' || p_etat;
        UTL_MAIL.SEND(
            sender     => 'noreply@retailchain.com',
            recipients => v_to,
            subject    => v_subject,
            message    => 'Le transfert <b>' || p_transfer_num || '</b> a été réceptionné par '
                         || p_reception_par || ' sur le site <b>' || p_dest_site || '</b>.<br>'
                         || 'État : ' || p_etat,
            mime_type  => 'text/html; charset=utf-8'
        );
        COMMIT;
    END;

    PROCEDURE job_daily_low_stock_alerts IS
    BEGIN
        FOR r IN (
            SELECT s.SITE_CODE, t.CODART, t.QTEPHYSIQUE, NVL(t.QTEMIN, NVL(t.QTESEC,0)) AS QTE_MIN
              FROM "TES-STOCK-SITE" t
              JOIN "TES-SITE" s ON s.ID = t.SITE_ID
             WHERE NVL(t.QTEPHYSIQUE,0) <= NVL(t.QTEMIN, NVL(t.QTESEC,0))
               AND s.ACTIVE='Y'
        ) LOOP
            notify_low_stock(r.SITE_CODE, r.CODART, r.QTEPHYSIQUE, r.QTE_MIN);
        END LOOP;
    END;

END pkg_notifications;
/

-- Job quotidien à 8h pour alerter les managers
BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
        job_name        => 'DAILY_LOW_STOCK_ALERTS',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN pkg_notifications.job_daily_low_stock_alerts; END;',
        start_date      => SYSDATE,
        repeat_interval => 'FREQ=DAILY;BYHOUR=8;BYMINUTE=0',
        enabled         => TRUE,
        auto_drop       => FALSE,
        comments        => 'Envoi quotidien des alertes stock bas aux managers de site'
    );
END;
/

PROMPT
PROMPT ====================================================================
PROMPT  Module Notifications installé :
PROMPT   - pkg_notifications.notify_low_stock
PROMPT   - pkg_notifications.notify_transfer_shipped
PROMPT   - pkg_notifications.notify_transfer_received
PROMPT   - Job DAILY_LOW_STOCK_ALERTS (08h00)
PROMPT
PROMPT  Nécessite : configurer SMTP Oracle :
PROMPT    DBMS_SCHEDULER.SET_AGENT_ATTRIBUTES(
PROMPT      'email_address', 'smtp.votredomaine.com:587',
PROMPT      'email_username', 'noreply@votredomaine.com',
PROMPT      'email_password', '***',
PROMPT      'email_use_ssl', 'Y');
PROMPT ====================================================================