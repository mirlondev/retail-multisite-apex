-- =====================================================================
-- 06_auth_schemes_apex.sql
-- Authorization Schemes PL/SQL pour APEX + câblage Authentication Scheme
--
-- Pour câbler dans APEX :
--   1. Admin APEX → Shared Components → Authentication Schemes
--   2. Créer un scheme "Custom PL/SQL Function Returning Boolean"
--   3. Fonction : RETURN ERP_APP.set_site_ctx_for_user(:APP_USER);
--   4. Cocher "Validate Session" = No
--
-- Pour les Authorization Schemes (à importer via ApexLang) :
--   Voir shared-components/authorizations.apx
-- =====================================================================

ALTER SESSION SET CURRENT_SCHEMA = ERP_APP;

-- Le package principal existe déjà (voir 05_authz_site_ctx.sql)
-- Ce script ajoute des variantes et utilitaires.

-- ---------------------------------------------------------------------
-- Helper : vérifier qu'un user peut créer un transfert vers un site donné
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION can_create_transfer_to(p_dest_site_id IN NUMBER) RETURN BOOLEAN IS
    v_role  VARCHAR2(30);
    v_user_site NUMBER;
BEGIN
    v_role := SYS_CONTEXT('SITE_CTX','USER_ROLE');
    v_user_site := TO_NUMBER(SYS_CONTEXT('SITE_CTX','SITE_ID'));

    -- HQ admin et depot peuvent tout faire
    IF v_role IN ('HQ_ADMIN','DEPOT_USER') THEN
        RETURN TRUE;
    END IF;

    -- SM manager : peut créer vers son dépôt parent ou HQ
    IF v_role = 'SM_MANAGER' THEN
        RETURN p_dest_site_id IN (
            SELECT ID FROM "TES-SITE" WHERE PARENT_SITE_ID = v_user_site
            UNION ALL
            SELECT PARENT_SITE_ID FROM "TES-SITE" WHERE ID = v_user_site
        );
    END IF;

    -- SM user simple : peut seulement créer vers son dépôt parent
    IF v_role = 'SM_USER' THEN
        RETURN p_dest_site_id = (
            SELECT PARENT_SITE_ID FROM "TES-SITE" WHERE ID = v_user_site
        );
    END IF;

    RETURN FALSE;
END;
/

-- ---------------------------------------------------------------------
-- Helper : vérifier qu'un user peut voir/éditer un transfert donné
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION can_access_transfer(p_transfer_id IN NUMBER) RETURN BOOLEAN IS
    v_role  VARCHAR2(30);
    v_user_site NUMBER;
    v_src    NUMBER;
    v_dst    NUMBER;
BEGIN
    v_role := SYS_CONTEXT('SITE_CTX','USER_ROLE');
    v_user_site := TO_NUMBER(SYS_CONTEXT('SITE_CTX','SITE_ID'));

    -- HQ admin : tout
    IF v_role = 'HQ_ADMIN' THEN
        RETURN TRUE;
    END IF;

    -- Récupérer source et destination
    SELECT SITE_SOURCE_ID, SITE_DEST_ID INTO v_src, v_dst
      FROM "TES-TRANSFER" WHERE ID = p_transfer_id;

    -- Dépôt / SM manager : accès si concerné
    IF v_role IN ('DEPOT_USER','SM_MANAGER') THEN
        RETURN v_src = v_user_site OR v_dst = v_user_site;
    END IF;

    -- SM user simple : seulement les transferts où son site est destination
    IF v_role = 'SM_USER' THEN
        RETURN v_dst = v_user_site;
    END IF;

    RETURN FALSE;
END;
/

-- ---------------------------------------------------------------------
-- Helper : récupérer le rôle de l'utilisateur courant (string util)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION current_role RETURN VARCHAR2 IS
BEGIN
    RETURN SYS_CONTEXT('SITE_CTX','USER_ROLE');
END;
/

CREATE OR REPLACE FUNCTION current_site_code RETURN VARCHAR2 IS
BEGIN
    RETURN SYS_CONTEXT('SITE_CTX','SITE_CODE');
END;
/

CREATE OR REPLACE FUNCTION current_site_id RETURN NUMBER IS
BEGIN
    RETURN TO_NUMBER(SYS_CONTEXT('SITE_CTX','SITE_ID'));
END;
/

-- ---------------------------------------------------------------------
-- Vue enrichie pour le contexte (utile dans les LOV APEX)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_current_user_ctx_full AS
SELECT
    SYS_CONTEXT('SITE_CTX','SITE_ID')    AS SITE_ID,
    SYS_CONTEXT('SITE_CTX','SITE_CODE')  AS SITE_CODE,
    SYS_CONTEXT('SITE_CTX','SITE_TYPE')  AS SITE_TYPE,
    SYS_CONTEXT('SITE_CTX','USER_ROLE')  AS USER_ROLE,
    SYS_CONTEXT('SITE_CTX','USERNAME')   AS USERNAME,
    CASE WHEN SYS_CONTEXT('SITE_CTX','USER_ROLE') = 'HQ_ADMIN' THEN 'Y' ELSE 'N' END AS IS_HQ,
    CASE WHEN SYS_CONTEXT('SITE_CTX','USER_ROLE') IN ('SM_USER','SM_MANAGER') THEN 'Y' ELSE 'N' END AS IS_SM,
    CASE WHEN SYS_CONTEXT('SITE_CTX','USER_ROLE') = 'DEPOT_USER' THEN 'Y' ELSE 'N' END AS IS_DEPOT,
    CASE WHEN SYS_CONTEXT('SITE_CTX','USER_ROLE') = 'SM_MANAGER' THEN 'Y' ELSE 'N' END AS IS_SM_MANAGER,
    CASE WHEN SYS_CONTEXT('SITE_CTX','USER_ROLE') = 'SM_USER' THEN 'Y' ELSE 'N' END AS IS_SM_USER
FROM DUAL;

GRANT SELECT ON v_current_user_ctx_full TO ERP_APP;

PROMPT
PROMPT ====================================================================
PROMPT  Authorization Helpers installés :
PROMPT   - can_create_transfer_to(site_id) : TRUE si le user peut demander un transfert
PROMPT   - can_access_transfer(transfer_id) : TRUE si le user peut voir/éditer
PROMPT   - current_role / current_site_code / current_site_id : helpers
PROMPT   - v_current_user_ctx_full : vue avec flags IS_HQ / IS_SM / IS_DEPOT
PROMPT ====================================================================

-- Test rapide
EXEC set_site_ctx_for_user('admin');
SELECT IS_HQ, IS_SM, IS_DEPOT, IS_SM_MANAGER FROM v_current_user_ctx_full;

EXEC set_site_ctx_for_user('caissier_sm1');
SELECT IS_HQ, IS_SM, IS_DEPOT, IS_SM_MANAGER FROM v_current_user_ctx_full;

EXEC set_site_ctx_for_user('depot_p');
SELECT IS_HQ, IS_SM, IS_DEPOT FROM v_current_user_ctx_full;