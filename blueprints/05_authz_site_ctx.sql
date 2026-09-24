-- =====================================================================
-- 05_authz_site_ctx.sql
-- Authentification multi-tenant APEX : pose le SITE_CTX selon l'utilisateur
-- =====================================================================

ALTER SESSION SET CURRENT_SCHEMA = ERP_APP;

-- =====================================================================
-- 05_authz_site_ctx.sql
-- Authentification multi-tenant APEX : pose le SITE_CTX selon l'utilisateur
-- =====================================================================

ALTER SESSION SET CURRENT_SCHEMA = ERP_APP;

-- ---------------------------------------------------------------------
-- Table des utilisateurs avec site par défaut
-- (Le CREATE TABLE est dans 01_schema_multisite.sql / _deploy_all.sql
--  Ce script installe les packages, fonctions et vue.)
-- ---------------------------------------------------------------------
-- Ne pas recréer la table si elle existe déjà (cohérence avec 01)
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE "TES-USER" CASCADE CONSTRAINTS PURGE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

CREATE TABLE "TES-USER" (
    ID              NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    USERNAME        VARCHAR2(100 CHAR) NOT NULL,
    USER_FULLNAME   VARCHAR2(400 CHAR),
    EMAIL           VARCHAR2(200 CHAR),
    SITE_ID         NUMBER NOT NULL,
    USER_ROLE       VARCHAR2(30 CHAR) DEFAULT 'SM_USER' NOT NULL,
    ACTIVE          VARCHAR2(1 CHAR) DEFAULT 'Y' NOT NULL,
    DATCRE          DATE DEFAULT SYSDATE NOT NULL,
    DATMOD          DATE,
    CONSTRAINT uk_tes_user_name UNIQUE (USERNAME),
    CONSTRAINT fk_tes_user_site FOREIGN KEY (SITE_ID) REFERENCES "TES-SITE"(ID),
    CONSTRAINT ck_tes_user_role CHECK (USER_ROLE IN ('HQ_ADMIN','SM_MANAGER','SM_USER','DEPOT_USER'))
);

CREATE INDEX idx_tes_user_site ON "TES-USER"(SITE_ID);

-- ---------------------------------------------------------------------
-- Seed d'utilisateurs de test
-- ---------------------------------------------------------------------
INSERT INTO "TES-USER" (USERNAME, USER_FULLNAME, EMAIL, SITE_ID, USER_ROLE) VALUES
    ('admin',        'Administrateur HQ',         'admin@retailchain.com',         (SELECT ID FROM "TES-SITE" WHERE SITE_CODE='HQ'),    'HQ_ADMIN');
INSERT INTO "TES-USER" (USERNAME, USER_FULLNAME, EMAIL, SITE_ID, USER_ROLE) VALUES
    ('manager_sm1',  'Manager Supermarché SM1',  'sm1.manager@retailchain.com',   (SELECT ID FROM "TES-SITE" WHERE SITE_CODE='SM1'),  'SM_MANAGER');
INSERT INTO "TES-USER" (USERNAME, USER_FULLNAME, EMAIL, SITE_ID, USER_ROLE) VALUES
    ('caissier_sm1', 'Caissier SM1',              'sm1.caissier@retailchain.com',  (SELECT ID FROM "TES-SITE" WHERE SITE_CODE='SM1'),  'SM_USER');
INSERT INTO "TES-USER" (USERNAME, USER_FULLNAME, EMAIL, SITE_ID, USER_ROLE) VALUES
    ('depot_p',      'Chef Dépôt Principal',     'depot.p@retailchain.com',       (SELECT ID FROM "TES-SITE" WHERE SITE_CODE='DEP_P'), 'DEPOT_USER');
COMMIT;

-- ---------------------------------------------------------------------
-- Procédure d'initialisation du contexte SITE_CTX
-- Appelée par APEX à chaque requête via une "Authentication Scheme" PL/SQL
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE set_site_ctx_for_user(p_username IN VARCHAR2) IS
    v_site_id NUMBER;
    v_site_code VARCHAR2(20);
    v_site_type VARCHAR2(30);
    v_role VARCHAR2(50);
BEGIN
    SELECT u.SITE_ID, s.SITE_CODE, s.SITE_TYPE, u.USER_ROLE
      INTO v_site_id, v_site_code, v_site_type, v_role
      FROM "TES-USER" u
      JOIN "TES-SITE" s ON s.ID = u.SITE_ID
     WHERE u.USERNAME = UPPER(p_username) AND u.ACTIVE='Y';

    DBMS_SESSION.SET_CONTEXT('SITE_CTX', 'SITE_ID', v_site_id);
    DBMS_SESSION.SET_CONTEXT('SITE_CTX', 'SITE_CODE', v_site_code);
    DBMS_SESSION.SET_CONTEXT('SITE_CTX', 'SITE_TYPE', v_site_type);
    DBMS_SESSION.SET_CONTEXT('SITE_CTX', 'USER_ROLE', v_role);
    DBMS_SESSION.SET_CONTEXT('SITE_CTX', 'USERNAME', UPPER(p_username));
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_SESSION.SET_CONTEXT('SITE_CTX', 'SITE_ID', NULL);
        DBMS_SESSION.SET_CONTEXT('SITE_CTX', 'SITE_CODE', 'NONE');
        DBMS_SESSION.SET_CONTEXT('SITE_CTX', 'SITE_TYPE', 'UNKNOWN');
END;
/

-- Permet à un utilisateur de basculer temporairement de contexte
CREATE OR REPLACE PROCEDURE switch_to_site(p_site_code IN VARCHAR2) IS
    v_role VARCHAR2(50);
    v_site_id NUMBER;
    v_site_type VARCHAR2(30);
BEGIN
    v_role := SYS_CONTEXT('SITE_CTX','USER_ROLE');

    -- Seuls HQ_ADMIN et DEPOT_USER peuvent basculer vers n'importe quel site
    IF v_role NOT IN ('HQ_ADMIN','DEPOT_USER') THEN
        RAISE_APPLICATION_ERROR(-20501, 'Seul le personnel HQ/Dépôt peut changer de site');
    END IF;

    SELECT ID, SITE_TYPE INTO v_site_id, v_site_type
      FROM "TES-SITE"
     WHERE SITE_CODE = p_site_code AND ACTIVE='Y';

    DBMS_SESSION.SET_CONTEXT('SITE_CTX', 'SITE_ID', v_site_id);
    DBMS_SESSION.SET_CONTEXT('SITE_CTX', 'SITE_CODE', p_site_code);
    DBMS_SESSION.SET_CONTEXT('SITE_CTX', 'SITE_TYPE', v_site_type);
END;
/

-- ---------------------------------------------------------------------
-- Procédure appelée par les Authorization Schemes APEX
-- ---------------------------------------------------------------------

-- Retourne TRUE si l'utilisateur peut accéder aux pages HQ
CREATE OR REPLACE FUNCTION is_hq_user RETURN BOOLEAN IS
    v_role VARCHAR2(50);
BEGIN
    v_role := SYS_CONTEXT('SITE_CTX','USER_ROLE');
    RETURN v_role = 'HQ_ADMIN';
END;
/

-- Retourne TRUE si l'utilisateur peut accéder aux pages SM (tous sauf HQ admin)
CREATE OR REPLACE FUNCTION is_sm_or_depot_user RETURN BOOLEAN IS
    v_role VARCHAR2(50);
BEGIN
    v_role := SYS_CONTEXT('SITE_CTX','USER_ROLE');
    RETURN v_role IN ('SM_USER','SM_MANAGER','DEPOT_USER','HQ_ADMIN');
END;
/

-- Vérifie que l'utilisateur travaille bien sur le site (par défaut ou switch)
CREATE OR REPLACE FUNCTION user_can_access_site(p_site_id IN NUMBER) RETURN BOOLEAN IS
    v_role VARCHAR2(50);
    v_user_site NUMBER;
BEGIN
    v_role := SYS_CONTEXT('SITE_CTX','USER_ROLE');
    v_user_site := TO_NUMBER(SYS_CONTEXT('SITE_CTX','SITE_ID'));
    -- HQ admin et depot peuvent tout voir
    IF v_role IN ('HQ_ADMIN','DEPOT_USER') THEN
        RETURN TRUE;
    END IF;
    -- SM manager/user : uniquement leur site
    RETURN v_user_site = p_site_id;
END;
/

-- Vue pour faciliter les vérifs depuis APEX
CREATE OR REPLACE VIEW v_current_user_ctx AS
SELECT
    SYS_CONTEXT('SITE_CTX','SITE_ID')    AS CURRENT_SITE_ID,
    SYS_CONTEXT('SITE_CTX','SITE_CODE')  AS CURRENT_SITE_CODE,
    SYS_CONTEXT('SITE_CTX','SITE_TYPE')  AS CURRENT_SITE_TYPE,
    SYS_CONTEXT('SITE_CTX','USER_ROLE')  AS CURRENT_USER_ROLE,
    SYS_CONTEXT('SITE_CTX','USERNAME')   AS CURRENT_USERNAME
FROM DUAL;

GRANT SELECT ON v_current_user_ctx TO ERP_APP;

PROMPT
PROMPT ====================================================================
PROMPT  Auth multi-tenant installée :
PROMPT   - Table TES-USER avec 4 users de test
PROMPT   - Procedure set_site_ctx_for_user : à câbler avec APEX Authentication Scheme
PROMPT   - Procedure switch_to_site : pour bascule HQ/DEPOT
PROMPT   - Functions is_hq_user / is_sm_or_depot_user / user_can_access_site
PROMPT   - Vue v_current_user_ctx : accès rapide au contexte
PROMPT ====================================================================

-- Test rapide
EXEC set_site_ctx_for_user('admin');
SELECT CURRENT_SITE_CODE, CURRENT_SITE_TYPE, CURRENT_USER_ROLE FROM v_current_user_ctx;

EXEC set_site_ctx_for_user('caissier_sm1');
SELECT CURRENT_SITE_CODE, CURRENT_SITE_TYPE, CURRENT_USER_ROLE FROM v_current_user_ctx;