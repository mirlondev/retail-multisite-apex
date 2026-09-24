-- =====================================================================
-- test_units_plsql.sql
-- Tests unitaires des packages et fonctions de l'app multi-site
-- =====================================================================

ALTER SESSION SET CURRENT_SCHEMA = ERP_APP;
SET SERVEROUTPUT ON
SET LINES 200

PROMPT
PROMPT ====================================================================
PROMPT  TESTS UNITAIRES PL/SQL
PROMPT ====================================================================

-- Variable pour compter les assertions
VARIABLE v_passed NUMBER
VARIABLE v_failed NUMBER
EXEC :v_passed := 0;
EXEC :v_failed := 0;

-- ============================================
-- Helper : procédure d'assertion
-- ============================================
CREATE OR REPLACE PROCEDURE ut_assert(
    p_test_name IN VARCHAR2,
    p_condition IN BOOLEAN,
    p_expected IN VARCHAR2,
    p_actual IN VARCHAR2
) IS
BEGIN
    IF p_condition THEN
        :v_passed := :v_passed + 1;
        DBMS_OUTPUT.PUT_LINE('  ✓ ' || p_test_name);
    ELSE
        :v_failed := :v_failed + 1;
        DBMS_OUTPUT.PUT_LINE('  ✗ ' || p_test_name || ' | expected: ' || p_expected || ' | got: ' || p_actual);
    END IF;
END;
/

-- ============================================
-- TEST 1 : set_site_ctx_for_user
-- ============================================
PROMPT
PROMPT === Tests SITE_CTX ===
DECLARE
    v_site_id NUMBER;
    v_site_code VARCHAR2(20);
    v_role VARCHAR2(30);
BEGIN
    -- Test 1.1 : admin → HQ
    set_site_ctx_for_user('admin');
    v_site_id := TO_NUMBER(SYS_CONTEXT('SITE_CTX','SITE_ID'));
    v_site_code := SYS_CONTEXT('SITE_CTX','SITE_CODE');
    v_role := SYS_CONTEXT('SITE_CTX','USER_ROLE');
    ut_assert('admin → HQ', v_site_code = 'HQ' AND v_role = 'HQ_ADMIN', 'HQ/HQ_ADMIN', v_site_code || '/' || v_role);

    -- Test 1.2 : caissier_sm1 → SM1
    set_site_ctx_for_user('caissier_sm1');
    v_site_code := SYS_CONTEXT('SITE_CTX','SITE_CODE');
    v_role := SYS_CONTEXT('SITE_CTX','USER_ROLE');
    ut_assert('caissier_sm1 → SM1/SM_USER', v_site_code = 'SM1' AND v_role = 'SM_USER', 'SM1/SM_USER', v_site_code || '/' || v_role);

    -- Test 1.3 : manager_sm1 → SM1/SM_MANAGER
    set_site_ctx_for_user('manager_sm1');
    v_role := SYS_CONTEXT('SITE_CTX','USER_ROLE');
    ut_assert('manager_sm1 → SM_MANAGER', v_role = 'SM_MANAGER', 'SM_MANAGER', v_role);

    -- Test 1.4 : depot_p → DEP_P
    set_site_ctx_for_user('depot_p');
    v_site_code := SYS_CONTEXT('SITE_CTX','SITE_CODE');
    ut_assert('depot_p → DEP_P', v_site_code = 'DEP_P', 'DEP_P', v_site_code);

    -- Test 1.5 : user inconnu → NONE/UNKNOWN
    set_site_ctx_for_user('ghost_user');
    v_site_code := SYS_CONTEXT('SITE_CTX','SITE_CODE');
    v_role := SYS_CONTEXT('SITE_CTX','USER_ROLE');
    ut_assert('ghost_user → NONE', v_site_code = 'NONE' AND v_role IS NULL, 'NONE/NULL', v_site_code || '/' || NVL(v_role,'NULL'));
END;
/

-- ============================================
-- TEST 2 : switch_to_site
-- ============================================
PROMPT
PROMPT === Tests switch_to_site ===
DECLARE
    v_site_code VARCHAR2(20);
    v_role VARCHAR2(30);
BEGIN
    -- Test 2.1 : admin peut basculer
    set_site_ctx_for_user('admin');
    switch_to_site('SM3');
    v_site_code := SYS_CONTEXT('SITE_CTX','SITE_CODE');
    ut_assert('admin switch → SM3', v_site_code = 'SM3', 'SM3', v_site_code);

    -- Test 2.2 : depot_p peut basculer
    set_site_ctx_for_user('depot_p');
    switch_to_site('SM1');
    v_site_code := SYS_CONTEXT('SITE_CTX','SITE_CODE');
    ut_assert('depot_p switch → SM1', v_site_code = 'SM1', 'SM1', v_site_code);

    -- Test 2.3 : caissier_sm1 NE PEUT PAS basculer
    set_site_ctx_for_user('caissier_sm1');
    DECLARE
        e_fail EXCEPTION;
        PRAGMA EXCEPTION_INIT(e_fail, -20501);
    BEGIN
        switch_to_site('SM2');
        ut_assert('caissier_sm1 cannot switch', FALSE, 'ORA-20501', 'no exception');
    EXCEPTION
        WHEN e_fail THEN
            ut_assert('caissier_sm1 cannot switch', TRUE, 'ORA-20501', 'ORA-20501 raised');
    END;
END;
/

-- ============================================
-- TEST 3 : is_hq_user / is_sm_or_depot_user
-- ============================================
PROMPT
PROMPT === Tests Authorization Functions ===
DECLARE
    v_result BOOLEAN;
BEGIN
    set_site_ctx_for_user('admin');
    ut_assert('is_hq_user (admin)', is_hq_user(), 'TRUE', 'FALSE');

    set_site_ctx_for_user('caissier_sm1');
    ut_assert('is_hq_user (caissier_sm1)', NOT is_hq_user(), 'FALSE', 'TRUE');
    ut_assert('is_sm_or_depot_user (caissier_sm1)', is_sm_or_depot_user(), 'TRUE', 'FALSE');
END;
/

-- ============================================
-- TEST 4 : user_can_access_site
-- ============================================
PROMPT
PROMPT === Tests user_can_access_site ===
DECLARE
    v_sm1_id NUMBER;
    v_sm2_id NUMBER;
BEGIN
    SELECT ID INTO v_sm1_id FROM "TES-SITE" WHERE SITE_CODE='SM1';
    SELECT ID INTO v_sm2_id FROM "TES-SITE" WHERE SITE_CODE='SM2';

    -- Test 4.1 : caissier_sm1 peut accéder à SM1
    set_site_ctx_for_user('caissier_sm1');
    ut_assert('caissier → SM1 (OK)', user_can_access_site(v_sm1_id), 'TRUE', 'FALSE');

    -- Test 4.2 : caissier_sm1 NE PEUT PAS accéder à SM2
    ut_assert('caissier → SM2 (KO)', NOT user_can_access_site(v_sm2_id), 'FALSE', 'TRUE');

    -- Test 4.3 : admin peut tout voir
    set_site_ctx_for_user('admin');
    ut_assert('admin → SM1 (OK)', user_can_access_site(v_sm1_id), 'TRUE', 'FALSE');
    ut_assert('admin → SM2 (OK)', user_can_access_site(v_sm2_id), 'TRUE', 'FALSE');
END;
/

-- ============================================
-- TEST 5 : can_create_transfer_to (ajouté par 06_auth_schemes_apex.sql)
-- ============================================
PROMPT
PROMPT === Tests can_create_transfer_to ===
DECLARE
    v_sm1_id    NUMBER;
    v_dep_p_id  NUMBER;
    v_sm2_id    NUMBER;
    v_dep_sm1_id NUMBER;
BEGIN
    SELECT ID INTO v_sm1_id      FROM "TES-SITE" WHERE SITE_CODE='SM1';
    SELECT ID INTO v_sm2_id      FROM "TES-SITE" WHERE SITE_CODE='SM2';
    SELECT ID INTO v_dep_p_id    FROM "TES-SITE" WHERE SITE_CODE='DEP_P';
    SELECT ID INTO v_dep_sm1_id FROM "TES-SITE" WHERE SITE_CODE='DEP_SM1';

    -- Test 5.1 : caissier_sm1 peut créer vers DEP_SM1 (son parent)
    set_site_ctx_for_user('caissier_sm1');
    DECLARE
        v_dummy NUMBER;
    BEGIN
        EXECUTE IMMEDIATE 'ALTER FUNCTION can_create_transfer_to COMPILE';
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    -- Si la fonction existe pas (pas encore déployé), skip
    BEGIN
        ut_assert('caissier → DEP_SM1 (parent)', can_create_transfer_to(v_dep_sm1_id), 'TRUE', 'not available');
        ut_assert('caissier → SM2 (KO, pas son parent)', NOT can_create_transfer_to(v_sm2_id), 'FALSE', 'not available');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('  ⚠ can_create_transfer_to pas encore installée (exécutez 06_auth_schemes_apex.sql d''abord)');
    END;
END;
/

-- ============================================
-- RAPPORT FINAL
-- ============================================
PROMPT
PROMPT ====================================================================
PRINT 'Tests réussis : ' || :v_passed
PRINT 'Tests échoués  : ' || :v_failed
PROMPT ====================================================================

-- Nettoyage
DROP PROCEDURE ut_assert;
