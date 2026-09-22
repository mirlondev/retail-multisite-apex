-- =====================================================================
-- 02_seed_sites.sql
-- Données initiales : 1 HQ + 1 Dépôt central + 5 Dépôts SM + 5 Supermarchés
-- =====================================================================

ALTER SESSION SET CURRENT_SCHEMA = ERP_APP;

-- HQ (siège)
INSERT INTO "TES-SITE" (SITE_CODE, SITE_NAME, SITE_TYPE, PARENT_SITE_ID, ADDRESS, CITY, ZIP_CODE, PHONE, EMAIL, RESP_NAME)
VALUES ('HQ', 'Siège Principal', 'HEAD_OFFICE', NULL, '15 rue de la Direction', 'Paris', '75001', '+33145001111', 'siege@retailchain.com', 'DG Directeur');

-- Dépôt principal
INSERT INTO "TES-SITE" (SITE_CODE, SITE_NAME, SITE_TYPE, PARENT_SITE_ID, ADDRESS, CITY, ZIP_CODE, PHONE, EMAIL, RESP_NAME)
VALUES ('DEP_P', 'Dépôt Principal Île-de-France', 'DEPOT_PRINCIPAL', (SELECT ID FROM "TES-SITE" WHERE SITE_CODE='HQ'),
        'Zone industrielle 4', 'Roissy', '95700', '+33145002222', 'depot.p@retailchain.com', 'Chef Dépôt Principal');

-- 5 Dépôts supermarchés + 5 Supermarchés
INSERT INTO "TES-SITE" (SITE_CODE, SITE_NAME, SITE_TYPE, PARENT_SITE_ID, CITY, RESP_NAME) VALUES
    ('DEP_SM1', 'Dépôt SM1', 'DEPOT_SM', (SELECT ID FROM "TES-SITE" WHERE SITE_CODE='DEP_P'), 'Lyon', 'Chef Dépôt SM1');
INSERT INTO "TES-SITE" (SITE_CODE, SITE_NAME, SITE_TYPE, PARENT_SITE_ID, CITY, ADDRESS, RESP_NAME) VALUES
    ('SM1', 'Supermarché Lyon Centre', 'SUPERMARKET', (SELECT ID FROM "TES-SITE" WHERE SITE_CODE='DEP_SM1'),
     'Lyon', '12 place Bellecour', 'Manager SM1');

INSERT INTO "TES-SITE" (SITE_CODE, SITE_NAME, SITE_TYPE, PARENT_SITE_ID, CITY, RESP_NAME) VALUES
    ('DEP_SM2', 'Dépôt SM2', 'DEPOT_SM', (SELECT ID FROM "TES-SITE" WHERE SITE_CODE='DEP_P'), 'Marseille', 'Chef Dépôt SM2');
INSERT INTO "TES-SITE" (SITE_CODE, SITE_NAME, SITE_TYPE, PARENT_SITE_ID, CITY, ADDRESS, RESP_NAME) VALUES
    ('SM2', 'Supermarché Marseille Prado', 'SUPERMARKET', (SELECT ID FROM "TES-SITE" WHERE SITE_CODE='DEP_SM2'),
     'Marseille', '34 avenue du Prado', 'Manager SM2');

INSERT INTO "TES-SITE" (SITE_CODE, SITE_NAME, SITE_TYPE, PARENT_SITE_ID, CITY, RESP_NAME) VALUES
    ('DEP_SM3', 'Dépôt SM3', 'DEPOT_SM', (SELECT ID FROM "TES-SITE" WHERE SITE_CODE='DEP_P'), 'Bordeaux', 'Chef Dépôt SM3');
INSERT INTO "TES-SITE" (SITE_CODE, SITE_NAME, SITE_TYPE, PARENT_SITE_ID, CITY, ADDRESS, RESP_NAME) VALUES
    ('SM3', 'Supermarché Bordeaux Sainte-Catherine', 'SUPERMARKET', (SELECT ID FROM "TES-SITE" WHERE SITE_CODE='DEP_SM3'),
     'Bordeaux', '56 rue Sainte-Catherine', 'Manager SM3');

INSERT INTO "TES-SITE" (SITE_CODE, SITE_NAME, SITE_TYPE, PARENT_SITE_ID, CITY, RESP_NAME) VALUES
    ('DEP_SM4', 'Dépôt SM4', 'DEPOT_SM', (SELECT ID FROM "TES-SITE" WHERE SITE_CODE='DEP_P'), 'Lille', 'Chef Dépôt SM4');
INSERT INTO "TES-SITE" (SITE_CODE, SITE_NAME, SITE_TYPE, PARENT_SITE_ID, CITY, ADDRESS, RESP_NAME) VALUES
    ('SM4', 'Supermarché Lille Euralille', 'SUPERMARKET', (SELECT ID FROM "TES-SITE" WHERE SITE_CODE='DEP_SM4'),
     'Lille', 'Avenue Willy Brandt', 'Manager SM4');

INSERT INTO "TES-SITE" (SITE_CODE, SITE_NAME, SITE_TYPE, PARENT_SITE_ID, CITY, RESP_NAME) VALUES
    ('DEP_SM5', 'Dépôt SM5', 'DEPOT_SM', (SELECT ID FROM "TES-SITE" WHERE SITE_CODE='DEP_P'), 'Nantes', 'Chef Dépôt SM5');
INSERT INTO "TES-SITE" (SITE_CODE, SITE_NAME, SITE_TYPE, PARENT_SITE_ID, CITY, ADDRESS, RESP_NAME) VALUES
    ('SM5', 'Supermarché Nantes Atlantis', 'SUPERMARKET', (SELECT ID FROM "TES-SITE" WHERE SITE_CODE='DEP_SM5'),
     'Nantes', 'Centre Commercial Atlantis', 'Manager SM5');

-- Magasins (caisse = sous-unité d'un supermarché)
INSERT INTO "TES-MAGASIN" (SITE_ID, MAGASIN_CODE, MAGASIN_NAME, CASHIER_COUNT, POS_COUNT)
SELECT ID, SITE_CODE || '-CAISSE-1', SITE_NAME || ' - Caisse Principale', 1, 1
FROM "TES-SITE" WHERE SITE_TYPE='SUPERMARKET';

INSERT INTO "TES-MAGASIN" (SITE_ID, MAGASIN_CODE, MAGASIN_NAME, CASHIER_COUNT, POS_COUNT)
SELECT ID, SITE_CODE || '-CAISSE-2', SITE_NAME || ' - Caisse Secondaire', 1, 1
FROM "TES-SITE" WHERE SITE_TYPE='SUPERMARKET';

-- Magasin du siège (achats / showroom)
INSERT INTO "TES-MAGASIN" (SITE_ID, MAGASIN_CODE, MAGASIN_NAME, CASHIER_COUNT, POS_COUNT)
SELECT ID, 'HQ-CAISSE-1', 'Siège - Bureau Achats', 1, 0
FROM "TES-SITE" WHERE SITE_CODE='HQ';

COMMIT;

PROMPT
PROMPT ====================================================================
PROMPT  Sites créés :
SELECT SITE_CODE, SITE_TYPE, CITY FROM "TES-SITE" ORDER BY ID;
PROMPT ====================================================================