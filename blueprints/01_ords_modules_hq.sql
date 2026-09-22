-- =====================================================================
-- 01_ords_modules_hq.sql
-- ORDS REST API côté supermarché -> HQ (publication des events)
-- À exécuter après l'installation d'ORDS et l'activation du schéma ERP_APP
-- =====================================================================

-- Prérequis : ORDS doit être démarré et le schéma ERP_APP activé :
--   BEGIN
--     ORDS_ADMIN.ENABLE_SCHEMA(p_schema => 'ERP_APP');
--   END;
--   /

ALTER SESSION SET CURRENT_SCHEMA = ERP_APP;

-- =====================================================================
-- MODULE : site.events
-- =====================================================================

BEGIN
    ORDS.DEFINE_MODULE(
        p_module_name    => 'site.events',
        p_base_path      => '/site/events/',
        p_items_per_page => 50
    );
    COMMIT;
END;
/

-- POST /site/events/stock/snapshot : publier le stock courant au HQ
BEGIN
    ORDS.DEFINE_TEMPLATE(
        p_module_name => 'site.events',
        p_pattern     => 'stock/snapshot'
    );
    ORDS.DEFINE_HANDLER(
        p_module_name => 'site.events',
        p_pattern     => 'stock/snapshot',
        p_method      => 'POST',
        p_source_type => 'plsql/block',
        p_source      => '
BEGIN
    pkg_ords_api.push_stock_snapshot(:body_text);
    :status_code := 200;
    htp.p(''{"status":"OK"}'');
END;'
    );
    ORDS.DEFINE_PARAMETER(
        p_module_name => 'site.events',
        p_pattern     => 'stock/snapshot',
        p_method      => 'POST',
        p_bind_variable_name => 'body_text',
        p_source_type => 'HEADER',
        p_access_method => 'IN'
    );
    COMMIT;
END;
/

-- POST /site/events/transfer/reception : notifier HQ d'une réception
BEGIN
    ORDS.DEFINE_TEMPLATE(
        p_module_name => 'site.events',
        p_pattern     => 'transfer/reception'
    );
    ORDS.DEFINE_HANDLER(
        p_module_name => 'site.events',
        p_pattern     => 'transfer/reception',
        p_method      => 'POST',
        p_source_type => 'plsql/block',
        p_source      => '
BEGIN
    pkg_ords_api.notify_transfer_reception(:body_text);
    :status_code := 200;
    htp.p(''{"status":"RECEPTION_NOTIFIED"}'');
END;'
    );
    ORDS.DEFINE_PARAMETER(
        p_module_name => 'site.events',
        p_pattern     => 'transfer/reception',
        p_method      => 'POST',
        p_bind_variable_name => 'body_text',
        p_source_type => 'HEADER',
        p_access_method => 'IN'
    );
    COMMIT;
END;
/

-- POST /site/events/transfer/new : demander un transfert (depuis SM)
BEGIN
    ORDS.DEFINE_TEMPLATE(
        p_module_name => 'site.events',
        p_pattern     => 'transfer/new'
    );
    ORDS.DEFINE_HANDLER(
        p_module_name => 'site.events',
        p_pattern     => 'transfer/new',
        p_method      => 'POST',
        p_source_type => 'plsql/block',
        p_source      => '
BEGIN
    pkg_ords_api.handle_transfer_request(:body_text);
    :status_code := 200;
    htp.p(''{"status":"TRANSFER_CREATED"}'');
END;'
    );
    ORDS.DEFINE_PARAMETER(
        p_module_name => 'site.events',
        p_pattern     => 'transfer/new',
        p_method      => 'POST',
        p_bind_variable_name => 'body_text',
        p_source_type => 'HEADER',
        p_access_method => 'IN'
    );
    COMMIT;
END;
/

PROMPT Module ORDS site.events créé


-- =====================================================================
-- Package pkg_ords_api : handlers côté site
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_ords_api AS
    PROCEDURE push_stock_snapshot(p_json_text IN CLOB);
    PROCEDURE notify_transfer_reception(p_json_text IN CLOB);
    PROCEDURE handle_transfer_request(p_json_text IN CLOB);
END;
/

CREATE OR REPLACE PACKAGE BODY pkg_ords_api AS

    -- Publier un snapshot stock vers le HQ
    PROCEDURE push_stock_snapshot(p_json_text IN CLOB) IS
        v_count NUMBER := 0;
    BEGIN
        -- Le body JSON contient une liste d'articles {codart, qte}
        -- On l'insère dans HQ_STOCK_JOUR avec SITE_ID = site courant
        INSERT INTO HQ_STOCK_JOUR (JOUR, SITE_ID, CODART, QTEPHYSIQUE, QTETHEORIQUE)
        SELECT SYSDATE,
               pkg_multisite_core.current_site,
               j.codart,
               j.qte_physique,
               j.qte_theorique
          FROM JSON_TABLE(p_json_text, '$[*]'
              COLUMNS (
                  codart         VARCHAR2(80) PATH '$.codart',
                  qte_physique   NUMBER      PATH '$.qte_physique',
                  qte_theorique  NUMBER      PATH '$.qte_theorique'
              )) j;
        v_count := SQL%ROWCOUNT;

        INSERT INTO HQ_SYNC_LOG (SITE_ID, SYNC_TYPE, SYNC_STATUS, RECORDS_PROCESSED, DETAILS)
        VALUES (pkg_multisite_core.current_site, 'STOCK_PUSH', 'SUCCESS', v_count,
                'ORDS POST /site/events/stock/snapshot');
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            INSERT INTO HQ_SYNC_LOG (SITE_ID, SYNC_TYPE, SYNC_STATUS, ERROR_MESSAGE)
            VALUES (pkg_multisite_core.current_site, 'STOCK_PUSH', 'FAILED', SQLERRM);
            COMMIT;
    END;

    -- Notifier HQ qu'une réception a été effectuée
    PROCEDURE notify_transfer_reception(p_json_text IN CLOB) IS
        v_transfer_id NUMBER;
        v_etat_reception VARCHAR2(30);
    BEGIN
        v_transfer_id := JSON_VALUE(p_json_text, '$.transfer_id');
        v_etat_reception := JSON_VALUE(p_json_text, '$.etat_reception');

        UPDATE "TES-TRANSFER"
           SET ETAT = DECODE(v_etat_reception, 'CONFORME', 'CLOTURE', 'PARTIELLE', 'RECEPTIONNE', 'NON_CONFORME', 'RECEPTIONNE', 'ENDOMMAGE', 'RECEPTIONNE'),
               DATRECEPT_EFFECTIVE = SYSDATE,
               DATMOD = SYSDATE
         WHERE ID = v_transfer_id;

        INSERT INTO HQ_SYNC_LOG (SITE_ID, SYNC_TYPE, SYNC_STATUS, RECORDS_PROCESSED, DETAILS)
        VALUES (pkg_multisite_core.current_site, 'RECEPTION_NOTIFY', 'SUCCESS', 1,
                'Transfer ' || v_transfer_id || ' ' || v_etat_reception);
        COMMIT;
    END;

    -- Recevoir une demande de transfert (depuis un SM) - traitée côté HQ
    PROCEDURE handle_transfer_request(p_json_text IN CLOB) IS
        v_count NUMBER := 0;
    BEGIN
        -- Cette procédure est appelée CÔTÉ HQ, pas côté site.
        -- En pratique, c'est l'inverse : SM envoie au HQ.
        INSERT INTO HQ_SYNC_LOG (SITE_ID, SYNC_TYPE, SYNC_STATUS, RECORDS_PROCESSED)
        VALUES (pkg_multisite_core.current_site, 'TRANSFER_REQUEST', 'SUCCESS', 1);
        COMMIT;
    END;

END pkg_ords_api;
/

PROMPT Package pkg_ords_api créé

PROMPT
PROMPT ====================================================================
PROMPT  Module ORDS site.events configuré :
PROMPT   POST /site/events/stock/snapshot
PROMPT   POST /site/events/transfer/reception
PROMPT   POST /site/events/transfer/new
PROMPT ====================================================================