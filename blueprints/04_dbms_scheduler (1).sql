-- =====================================================================
-- 04_dbms_scheduler.sql
-- Jobs de synchronisation et agrégation HQ
-- =====================================================================

ALTER SESSION SET CURRENT_SCHEMA = ERP_APP;

-- ---------------------------------------------------------------------
-- Job : SYNC_HQ_AGG_DAILY
-- Agrégation quotidienne des ventes multi-sites (HQ)
-- Tourne chaque nuit à 00h30
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE aggregate_hq_ventes_jour IS
BEGIN
    -- Agréger les ventes de la veille depuis le schéma TRANSFERT
    MERGE INTO "HQ_VENTES_JOUR" t
    USING (
        SELECT TRUNC(SYSDATE - 1) AS JOUR,
               (SELECT ID FROM "TES-SITE" WHERE SITE_CODE='HQ') AS SITE_ID,
               COUNT(*) AS NUMTICKETS,
                   SUM(NVL(MONTANTTTC,0)) AS TOTAL_TTC,
                   SUM(NVL(MONTANTHT,0)) AS TOTAL_HT,
                   SUM(NVL(MONTANT_REMISE,0)) AS TOTAL_REMISE,
                   SUM(NVL(MONTANTTTC,0) - NVL(MONTANT_REMISE,0)) AS TOTAL_NET
          FROM TRANSFERT."CETICKET_ARCH"
         WHERE TRUNC(DATCRE) = TRUNC(SYSDATE - 1)
    ) s
    ON (t.JOUR = s.JOUR AND t.SITE_ID = s.SITE_ID)
    WHEN MATCHED THEN UPDATE SET
        t.NUMTICKETS = s.NUMTICKETS,
        t.TOTAL_TTC = s.TOTAL_TTC,
        t.TOTAL_HT = s.TOTAL_HT,
        t.TOTAL_REMISE = s.TOTAL_REMISE,
        t.TOTAL_NET = s.TOTAL_NET
    WHEN NOT MATCHED THEN INSERT
        (JOUR, SITE_ID, NUMTICKETS, TOTAL_TTC, TOTAL_HT, TOTAL_REMISE, TOTAL_NET)
    VALUES
        (s.JOUR, s.SITE_ID, s.NUMTICKETS, s.TOTAL_TTC, s.TOTAL_HT, s.TOTAL_REMISE, s.TOTAL_NET);

    INSERT INTO "HQ_SYNC_LOG" (SITE_ID, SYNC_TYPE, SYNC_STATUS, RECORDS_PROCESSED)
    VALUES ((SELECT ID FROM "TES-SITE" WHERE SITE_CODE='HQ'), 'AGG_VENTES', 'SUCCESS', SQL%ROWCOUNT);
    COMMIT;
END;
/

BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
        job_name        => 'AGG_HQ_VENTES_DAILY',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN aggregate_hq_ventes_jour; END;',
        start_date      => SYSDATE,
        repeat_interval => 'FREQ=DAILY;BYHOUR=0;BYMINUTE=30',
        enabled         => TRUE,
        auto_drop       => FALSE,
        comments        => 'Agrégation HQ des ventes de la veille (tous sites)'
    );
END;
/

-- ---------------------------------------------------------------------
-- Job : INTEGRATE_TRANSFERT_BUFFER
-- Intégration des données du buffer TRANSFERT vers les tables HQ
-- Tourne tous les jours à 23h30
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE integrate_transfert_buffer IS
    v_count NUMBER := 0;
BEGIN
    -- Pour l'instant, simple log (à étendre selon les besoins métier)
    INSERT INTO "HQ_SYNC_LOG" (SITE_ID, SYNC_TYPE, SYNC_STATUS, RECORDS_PROCESSED, DETAILS)
    SELECT (SELECT ID FROM "TES-SITE" WHERE SITE_CODE='HQ'),
           'TRANSFERT_INTEGRATION', 'SUCCESS', COUNT(*),
           'Lignes TRANSFERT.GL_* détectées pour J-1'
      FROM TRANSFERT."TR_GCBRDD"
     WHERE TRUNC(DATCRE) = TRUNC(SYSDATE - 1);

    v_count := SQL%ROWCOUNT;
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        INSERT INTO "HQ_SYNC_LOG" (SITE_ID, SYNC_TYPE, SYNC_STATUS, ERROR_MESSAGE)
        VALUES ((SELECT ID FROM "TES-SITE" WHERE SITE_CODE='HQ'),
                'TRANSFERT_INTEGRATION', 'FAILED', SQLERRM);
        COMMIT;
END;
/

BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
        job_name        => 'INTEGRATE_TRANSFERT_BUFFER',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN integrate_transfert_buffer; END;',
        start_date      => SYSDATE,
        repeat_interval => 'FREQ=DAILY;BYHOUR=23;BYMINUTE=30',
        enabled         => TRUE,
        auto_drop       => FALSE,
        comments        => 'Intégration des données du buffer TRANSFERT vers HQ'
    );
END;
/

-- ---------------------------------------------------------------------
-- Job : ALERT_LOW_STOCK
-- Détection des ruptures de stock (toutes les 4h)
-- Insère dans TES-SITE-AUDIT pour notification APEX
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE alert_low_stock IS
BEGIN
    INSERT INTO "TES-SITE-AUDIT" (SITE_ID, AUDIT_TYPE, ENTITY_TABLE, ACTION, DETAILS)
    SELECT s.SITE_ID, 'STOCK_ALERTE', 'TES-STOCK-SITE', 'ALERT',
           'Article ' || s.CODART || ' en alerte : ' || s.QTEPHYSIQUE ||
           ' (min=' || NVL(s.QTEMIN,0) || ', sec=' || NVL(s.QTESEC,0) || ')'
      FROM "TES-STOCK-SITE" s
     WHERE NVL(s.QTEPHYSIQUE,0) <= NVL(s.QTEMIN, NVL(s.QTESEC,0));
    COMMIT;
END;
/

BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
        job_name        => 'ALERT_LOW_STOCK',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN alert_low_stock; END;',
        start_date      => SYSDATE,
        repeat_interval => 'FREQ=HOURLY;INTERVAL=4',
        enabled         => TRUE,
        auto_drop       => FALSE,
        comments        => 'Détection des articles en rupture/alert stock'
    );
END;
/

-- ---------------------------------------------------------------------
-- Job : NETTOYAGE AUDIT > 90 jours
-- ---------------------------------------------------------------------
BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
        job_name        => 'PURGE_OLD_AUDIT',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'DELETE FROM "TES-SITE-AUDIT" WHERE AUDIT_DATETIME < SYSDATE - 90; COMMIT;',
        start_date      => SYSDATE,
        repeat_interval => 'FREQ=DAILY;BYHOUR=2',
        enabled         => TRUE,
        auto_drop       => FALSE,
        comments        => 'Purge audit logs > 90 jours'
    );
END;
/

PROMPT
PROMPT ====================================================================
PROMPT  Jobs DBMS_SCHEDULER installés :
PROMPT   - AGG_HQ_VENTES_DAILY (00h30)        : agrégation HQ des ventes
PROMPT   - INTEGRATE_TRANSFERT_BUFFER (23h30) : intégration buffer -> HQ
PROMPT   - ALERT_LOW_STOCK (toutes 4h)        : alertes stock
PROMPT   - PURGE_OLD_AUDIT (02h00)            : purge audit > 90j
PROMPT ====================================================================

-- Vérification
SELECT job_name, enabled, repeat_interval FROM user_scheduler_jobs
 WHERE job_name IN ('AGG_HQ_VENTES_DAILY','INTEGRATE_TRANSFERT_BUFFER','ALERT_LOW_STOCK','PURGE_OLD_AUDIT')
 ORDER BY job_name;