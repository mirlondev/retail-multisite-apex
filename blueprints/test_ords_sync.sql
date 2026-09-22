-- =====================================================================
-- test_ords_sync.sql
-- Test du pipeline ORDS : SM1 pousse un snapshot stock au HQ
-- =====================================================================

ALTER SESSION SET CURRENT_SCHEMA = ERP_APP;

PROMPT
PROMPT ====================================================================
PROMPT  TEST ORDS - Push stock snapshot SM1 -> HQ
PROMPT ====================================================================

-- 1. Se mettre dans le contexte SM1
PROMPT 1. Activation contexte SM1
CALL pkg_multisite_core.set_site_ctx_for_user('caissier_sm1');
SELECT CURRENT_SITE_CODE, CURRENT_SITE_TYPE FROM v_current_user_ctx;

-- 2. Simuler un snapshot JSON du stock de SM1
PROMPT
PROMPT 2. Préparation du payload JSON (snapshot stock)
DECLARE
    v_json CLOB := '{"snapshot":[
        {"codart":"ART-001","qte_physique":12.5,"qte_theorique":15.0},
        {"codart":"ART-002","qte_physique":0,"qte_theorique":50.0},
        {"codart":"ART-003","qte_physique":120,"qte_theorique":120.0}
    ]}';
BEGIN
    pkg_ords_api.push_stock_snapshot(v_json);
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Snapshot poussé.');
END;
/

-- 3. Vérifier que le HQ a bien reçu
PROMPT
PROMPT 3. Vérification côté HQ (HQ_STOCK_JOUR)
SELECT JOUR, s.SITE_CODE, CODART, QTEPHYSIQUE, QTETHEORIQUE
  FROM HQ_STOCK_JOUR h
  JOIN "TES-SITE" s ON s.ID = h.SITE_ID
 ORDER BY h.DATCRE DESC, s.SITE_CODE
 FETCH FIRST 10 ROWS ONLY;

PROMPT
PROMPT 4. Vérification du log de synchro
SELECT SYNC_DATETIME, s.SITE_CODE, SYNC_TYPE, SYNC_STATUS, RECORDS_PROCESSED, DETAILS
  FROM HQ_SYNC_LOG h
  LEFT JOIN "TES-SITE" s ON s.ID = h.SITE_ID
 ORDER BY h.SYNC_DATETIME DESC
 FETCH FIRST 5 ROWS ONLY;

PROMPT
PROMPT 5. Bascule vers HQ (admin)
CALL pkg_multisite_core.set_site_ctx_for_user('admin');
SELECT CURRENT_SITE_CODE, CURRENT_SITE_TYPE FROM v_current_user_ctx;

PROMPT
PROMPT 6. Test switch_to_site (admin -> SM1)
CALL pkg_multisite_core.switch_to_site('SM1');
SELECT CURRENT_SITE_CODE, CURRENT_SITE_TYPE FROM v_current_user_ctx;

PROMPT
PROMPT 7. Retour HQ
CALL pkg_multisite_core.switch_to_site('HQ');
SELECT CURRENT_SITE_CODE, CURRENT_SITE_TYPE FROM v_current_user_ctx;

PROMPT
PROMPT ====================================================================
PROMPT  FIN TEST ORDS
PROMPT ====================================================================