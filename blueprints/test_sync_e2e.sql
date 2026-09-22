-- =====================================================================
-- test_sync_e2e.sql
-- Test bout-en-bout de la chaîne de transfert
-- Scénario : SM1 demande au dépôt parent, dépôt livre, SM1 réceptionne
-- =====================================================================

ALTER SESSION SET CURRENT_SCHEMA = ERP_APP;

SET SERVEROUTPUT ON
SET LINES 200

PROMPT
PROMPT ====================================================================
PROMPT  TEST E2E - Transfert SM1 -> Depot -> SM1
PROMPT ====================================================================

-- Vérifier que les sites existent
PROMPT Vérification des sites nécessaires...
SELECT 'SM1' AS ROLE, COUNT(*) AS EXISTS_CNT FROM "TES-SITE" WHERE SITE_CODE='SM1'
UNION ALL
SELECT 'DEP_SM1', COUNT(*) FROM "TES-SITE" WHERE SITE_CODE='DEP_SM1';

-- Vérifier que les packages existent
PROMPT Vérification des packages installés...
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_type IN ('PACKAGE','PACKAGE BODY')
   AND object_name IN ('PKG_MULTISITE_CORE','PKG_TRANSFER','PKG_STOCK')
 ORDER BY object_name;

-- Initialiser un peu de stock pour les tests
PROMPT Stock initial pour SM1 (article TEST-001)...
MERGE INTO "TES-STOCK-SITE" t
USING (SELECT (SELECT ID FROM "TES-SITE" WHERE SITE_CODE='SM1') AS SITE_ID,
              'TEST-001' AS CODART,
              10 AS QTE FROM DUAL) s
ON (t.SITE_ID = s.SITE_ID AND t.CODART = s.CODART)
WHEN MATCHED THEN UPDATE SET QTEPHYSIQUE = s.QTE, QTETHEORIQUE = s.QTE, DATMOD = SYSDATE
WHEN NOT MATCHED THEN INSERT (SITE_ID, CODART, QTEPHYSIQUE, QTETHEORIQUE)
VALUES (s.SITE_ID, s.CODART, s.QTE, s.QTE);
COMMIT;

PROMPT
PROMPT === TEST 1 : SM1 demande un transfert à son dépôt parent ===
DECLARE
    v_tab          pkg_transfer.t_lignes_tab := pkg_transfer.t_lignes_tab();
    v_id           NUMBER;
    v_num          VARCHAR2(20);
    v_current_site NUMBER;
BEGIN
    -- Se positionner sur SM1
    SELECT ID INTO v_current_site FROM "TES-SITE" WHERE SITE_CODE='SM1';
    DBMS_APPLICATION_INFO.SET_CLIENT_INFO(v_current_site);
    -- Pour ce test, on triche en modifiant g_default_site_id via package
    -- (en vrai, ce sera via le contexte SITE_CTX posé par APEX)

    v_tab.EXTEND(2);
    v_tab(1).codart := 'TEST-001'; v_tab(1).qte := 50;
    v_tab(2).codart := 'TEST-002'; v_tab(2).qte := 100;

    -- Note : on ne peut pas appeler pkg_multisite_core.current_site depuis un script
    -- sans avoir posé le contexte. En pratique, c'est APEX qui le fait via une proc d'auth.
    -- Ici on simule :
    EXECUTE IMMEDIATE 'ALTER SESSION SET current_schema = ERP_APP';
    EXECUTE IMMEDIATE 'BEGIN pkg_transfer.create_transfer(''DEP_SM1'', ''URGENTE'', NULL, ''Test E2E'', :1, :2, :3); END;'
        USING IN v_tab, OUT v_id, OUT v_num;

    DBMS_OUTPUT.PUT_LINE('Demande créée : ' || v_num || ' (ID=' || v_id || ')');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Erreur test 1 : ' || SQLERRM);
END;
/

PROMPT
PROMPT === TEST 2 : Liste des transferts en cours ===
SELECT t.ID, t.TRANSFER_NUM,
       src.SITE_CODE AS SRC, dst.SITE_CODE AS DST,
       t.ETAT, t.PRIORITY, t.DATDEMANDE,
       (SELECT COUNT(*) FROM "TES-TRANSFER-LINE" l WHERE l.TRANSFER_ID=t.ID) AS NB_LIGNES
  FROM "TES-TRANSFER" t
  JOIN "TES-SITE" src ON src.ID = t.SITE_SOURCE_ID
  JOIN "TES-SITE" dst ON dst.ID = t.SITE_DEST_ID
 ORDER BY t.DATDEMANDE DESC
 FETCH FIRST 5 ROWS ONLY;

PROMPT
PROMPT === TEST 3 : Validation + Expédition par le dépôt ===
DECLARE
    v_id NUMBER;
BEGIN
    SELECT ID INTO v_id FROM "TES-TRANSFER"
     WHERE ETAT='DEMANDE'
       AND SITE_SOURCE_ID=(SELECT ID FROM "TES-SITE" WHERE SITE_CODE='DEP_SM1')
       AND SITE_DEST_ID=(SELECT ID FROM "TES-SITE" WHERE SITE_CODE='SM1')
       AND ROWNUM=1;
    pkg_transfer.validate_transfer(v_id);
    pkg_transfer.ship_transfer(v_id, 2, 'TEST_USER');
    DBMS_OUTPUT.PUT_LINE('Transfert ' || v_id || ' expédié');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Erreur test 3 : ' || SQLERRM);
END;
/

PROMPT
PROMPT === TEST 4 : Réception par SM1 ===
DECLARE
    v_id NUMBER;
BEGIN
    SELECT ID INTO v_id FROM "TES-TRANSFER"
     WHERE ETAT='EN_TRANSIT'
       AND SITE_DEST_ID=(SELECT ID FROM "TES-SITE" WHERE SITE_CODE='SM1')
       AND ROWNUM=1;
    pkg_transfer.receive_transfer(
        p_transfer_id     => v_id,
        p_receptionne_par => 'TEST_USER',
        p_etat_reception  => 'CONFORME',
        p_colis_attendus  => 2,
        p_colis_recus     => 2,
        p_commentaire     => 'Test E2E OK'
    );
    DBMS_OUTPUT.PUT_LINE('Transfert ' || v_id || ' réceptionné');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Erreur test 4 : ' || SQLERRM);
END;
/

PROMPT
PROMPT === TEST 5 : État du stock SM1 après transfert ===
SELECT s.CODART, s.QTEPHYSIQUE, s.QTETHEORIQUE, s.QTEENTRANSIT, s.DERNIER_MVT
  FROM "TES-STOCK-SITE" s
 WHERE s.SITE_ID=(SELECT ID FROM "TES-SITE" WHERE SITE_CODE='SM1')
   AND s.CODART LIKE 'TEST-%'
 ORDER BY s.CODART;

PROMPT
PROMPT === TEST 6 : Audit log des actions ===
SELECT TO_CHAR(AUDIT_DATETIME, 'HH24:MI:SS') AS HEURE,
       s.SITE_CODE, AUDIT_TYPE, ACTION, USER_NAME, DETAILS
  FROM "TES-SITE-AUDIT" a
  LEFT JOIN "TES-SITE" s ON s.ID = a.SITE_ID
 ORDER BY a.AUDIT_DATETIME DESC
 FETCH FIRST 10 ROWS ONLY;

PROMPT
PROMPT ====================================================================
PROMPT  FIN DU TEST E2E
PROMPT ====================================================================