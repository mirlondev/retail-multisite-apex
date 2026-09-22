-- =====================================================================
-- 01_schema_multisite.sql
-- DDL des tables multi-sites pour chaîne de supermarchés
-- Cible: Oracle 21c XE
-- =====================================================================

ALTER SESSION SET CURRENT_SCHEMA = ERP_APP;

-- ---------------------------------------------------------------------
-- Tables de configuration (référentiel)
-- ---------------------------------------------------------------------

-- 1. Table des sites
CREATE TABLE "TES-SITE" (
    ID              NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    SITE_CODE       VARCHAR2(20 CHAR) NOT NULL,
    SITE_NAME       VARCHAR2(200 CHAR) NOT NULL,
    SITE_TYPE       VARCHAR2(30 CHAR) NOT NULL,  -- HEAD_OFFICE, DEPOT_PRINCIPAL, DEPOT_SM, SUPERMARKET
    PARENT_SITE_ID  NUMBER,
    ADDRESS         VARCHAR2(255 CHAR),
    CITY            VARCHAR2(100 CHAR),
    ZIP_CODE        VARCHAR2(20 CHAR),
    PHONE           VARCHAR2(30 CHAR),
    EMAIL           VARCHAR2(200 CHAR),
    RESP_NAME       VARCHAR2(200 CHAR),
    ACTIVE          VARCHAR2(1 CHAR) DEFAULT 'Y' NOT NULL,
    DATCRE          DATE DEFAULT SYSDATE NOT NULL,
    DATMOD          DATE,
    CONSTRAINT uk_tes_site_code UNIQUE (SITE_CODE),
    CONSTRAINT ck_tes_site_type CHECK (SITE_TYPE IN ('HEAD_OFFICE','DEPOT_PRINCIPAL','DEPOT_SM','SUPERMARKET')),
    CONSTRAINT ck_tes_site_active CHECK (ACTIVE IN ('Y','N'))
);

COMMENT ON TABLE "TES-SITE" IS 'Référentiel des sites de la chaîne (HQ, dépôts, supermarchés)';
COMMENT ON COLUMN "TES-SITE".SITE_TYPE IS 'Type de site : HQ, dépôt central, dépôt SM, supermarché';

CREATE INDEX idx_tes_site_type ON "TES-SITE"(SITE_TYPE);
CREATE INDEX idx_tes_site_parent ON "TES-SITE"(PARENT_SITE_ID);

-- 2. Table des magasins (un supermarché peut avoir 1+ caisses physiques)
CREATE TABLE "TES-MAGASIN" (
    ID              NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    SITE_ID         NUMBER NOT NULL,
    MAGASIN_CODE    VARCHAR2(20 CHAR) NOT NULL,
    MAGASIN_NAME    VARCHAR2(200 CHAR) NOT NULL,
    MAGASIN_TYPE    VARCHAR2(30 CHAR) DEFAULT 'PRINCIPAL',
    CASHIER_COUNT   NUMBER DEFAULT 1,
    POS_COUNT       NUMBER DEFAULT 1,
    ACTIVE          VARCHAR2(1 CHAR) DEFAULT 'Y' NOT NULL,
    DATCRE          DATE DEFAULT SYSDATE NOT NULL,
    DATMOD          DATE,
    CONSTRAINT uk_tes_magasin_code UNIQUE (MAGASIN_CODE),
    CONSTRAINT fk_tes_magasin_site FOREIGN KEY (SITE_ID) REFERENCES "TES-SITE"(ID)
);

COMMENT ON TABLE "TES-MAGASIN" IS 'Magasins / caisses physiques rattachés à un site';

-- ---------------------------------------------------------------------
-- Tables métier
-- ---------------------------------------------------------------------

-- 3. Stock par site
CREATE TABLE "TES-STOCK-SITE" (
    ID              NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    SITE_ID         NUMBER NOT NULL,
    CODART          VARCHAR2(80 CHAR) NOT NULL,
    QTEPHYSIQUE     NUMBER(16,4) DEFAULT 0,    -- stock réel (post inventaire)
    QTETHEORIQUE    NUMBER(16,4) DEFAULT 0,    -- stock système
    QTEMIN          NUMBER(16,4),
    QTEMAX          NUMBER(16,4),
    QTESEC          NUMBER(16,4),
    QTECOMMANDE     NUMBER(16,4) DEFAULT 0,    -- en commande fournisseur
    QTEENTRANSIT    NUMBER(16,4) DEFAULT 0,    -- en transfert entrant
    DERNIER_MVT     DATE,
    DATCRE          DATE DEFAULT SYSDATE NOT NULL,
    DATMOD          DATE,
    CONSTRAINT uk_tes_stock_site UNIQUE (SITE_ID, CODART),
    CONSTRAINT fk_tes_stock_site_site FOREIGN KEY (SITE_ID) REFERENCES "TES-SITE"(ID)
);

CREATE INDEX idx_tes_stock_site_codart ON "TES-STOCK-SITE"(CODART);
CREATE INDEX idx_tes_stock_site_alerte ON "TES-STOCK-SITE"(SITE_ID, QTEMIN, QTEPHYSIQUE);

COMMENT ON TABLE "TES-STOCK-SITE" IS 'Stock par site et par article (physique + théorique)';
COMMENT ON COLUMN "TES-STOCK-SITE".QTEENTRANSIT IS 'Quantité en cours de transfert entrant depuis un autre site';

-- 4. Transferts inter-sites (ordres de transfert)
CREATE TABLE "TES-TRANSFER" (
    ID              NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    TRANSFER_NUM    VARCHAR2(20 CHAR) NOT NULL,
    SITE_SOURCE_ID  NUMBER NOT NULL,
    SITE_DEST_ID    NUMBER NOT NULL,
    DATDEMANDE      DATE DEFAULT SYSDATE NOT NULL,
    DATENVOI_SOUHAITEE DATE,
    DATRECEPT_SOUHAITEE DATE,
    DATENVOI_EFFECTIVE DATE,
    DATRECEPT_EFFECTIVE DATE,
    ETAT            VARCHAR2(30 CHAR) DEFAULT 'DEMANDE' NOT NULL,
    PRIORITY        VARCHAR2(20 CHAR) DEFAULT 'NORMALE' NOT NULL,
    TRANSPORT_MODE  VARCHAR2(30 CHAR),
    NUM_BORDEREAU   VARCHAR2(30 CHAR),
    CUTI_DEMANDE    VARCHAR2(20 CHAR),
    CUTI_ENVOI      VARCHAR2(20 CHAR),
    CUTI_RECEPT     VARCHAR2(20 CHAR),
    COMMENTAIRE_DEMANDE  VARCHAR2(1000 CHAR),
    COMMENTAIRE_ENVOI    VARCHAR2(1000 CHAR),
    COMMENTAIRE_RECEPT   VARCHAR2(1000 CHAR),
    DATCRE          DATE DEFAULT SYSDATE NOT NULL,
    DATMOD          DATE,
    CONSTRAINT uk_tes_transfer_num UNIQUE (TRANSFER_NUM),
    CONSTRAINT fk_tes_transfer_src FOREIGN KEY (SITE_SOURCE_ID) REFERENCES "TES-SITE"(ID),
    CONSTRAINT fk_tes_transfer_dst FOREIGN KEY (SITE_DEST_ID) REFERENCES "TES-SITE"(ID),
    CONSTRAINT ck_tes_transfer_etat CHECK (ETAT IN (
        'DEMANDE','VALIDE','EN_PREPARATION','EN_TRANSIT','RECEPTIONNE','CLOTURE','ANNULE')),
    CONSTRAINT ck_tes_transfer_priority CHECK (PRIORITY IN ('NORMALE','URGENTE','CRITIQUE'))
);

CREATE INDEX idx_tes_transfer_etat ON "TES-TRANSFER"(ETAT);
CREATE INDEX idx_tes_transfer_src ON "TES-TRANSFER"(SITE_SOURCE_ID);
CREATE INDEX idx_tes_transfer_dst ON "TES-TRANSFER"(SITE_DEST_ID);
CREATE INDEX idx_tes_transfer_datdemande ON "TES-TRANSFER"(DATDEMANDE DESC);

-- 5. Lignes de transfert
CREATE TABLE "TES-TRANSFER-LINE" (
    ID              NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    TRANSFER_ID     NUMBER NOT NULL,
    NUMLIG          NUMBER NOT NULL,
    CODART          VARCHAR2(80 CHAR) NOT NULL,
    QTEDEMANDEE     NUMBER(16,4) NOT NULL,
    QTEPREPAREE     NUMBER(16,4) DEFAULT 0,
    QTEEXPEDIEE     NUMBER(16,4) DEFAULT 0,
    QTERECEPTIONNEE NUMBER(16,4) DEFAULT 0,
    PRIX_UNITAIRE   NUMBER(16,4),
    COMMENTAIRE     VARCHAR2(500 CHAR),
    DATCRE          DATE DEFAULT SYSDATE NOT NULL,
    DATMOD          DATE,
    CONSTRAINT uk_tes_transfer_line UNIQUE (TRANSFER_ID, NUMLIG),
    CONSTRAINT fk_tes_transfer_line FOREIGN KEY (TRANSFER_ID) REFERENCES "TES-TRANSFER"(ID) ON DELETE CASCADE
);

CREATE INDEX idx_tes_transfer_line_art ON "TES-TRANSFER-LINE"(CODART);

-- 6. Réception (signée) d'un transfert
CREATE TABLE "TES-TRANSFER-RECEPTION" (
    ID              NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    TRANSFER_ID     NUMBER NOT NULL,
    DATRECEPTION    DATE DEFAULT SYSDATE NOT NULL,
    RECEPTIONNE_PAR VARCHAR2(200 CHAR) NOT NULL,
    ETAT_RECEPTION  VARCHAR2(30 CHAR) DEFAULT 'CONFORME' NOT NULL,
    NB_COLIS_ATTENDUS NUMBER,
    NB_COLIS_RECUS   NUMBER,
    COMMENTAIRE     VARCHAR2(1000 CHAR),
    DATCRE          DATE DEFAULT SYSDATE NOT NULL,
    CONSTRAINT uk_tes_reception_transfer UNIQUE (TRANSFER_ID),
    CONSTRAINT fk_tes_reception_transfer FOREIGN KEY (TRANSFER_ID) REFERENCES "TES-TRANSFER"(ID),
    CONSTRAINT ck_tes_reception_etat CHECK (ETAT_RECEPTION IN ('CONFORME','PARTIELLE','NON_CONFORME','ENDOMMAGE'))
);

-- 7. Audit log des opérations multi-site
CREATE TABLE "TES-SITE-AUDIT" (
    ID              NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    SITE_ID         NUMBER,
    AUDIT_TYPE      VARCHAR2(50 CHAR) NOT NULL,   -- SYNC_PUSH, SYNC_PULL, TRANSFER_CREATED, STOCK_UPDATED
    ENTITY_TABLE    VARCHAR2(50 CHAR),
    ENTITY_ID       NUMBER,
    ACTION          VARCHAR2(50 CHAR),
    USER_NAME       VARCHAR2(200 CHAR),
    DETAILS         VARCHAR2(4000 CHAR),
    AUDIT_DATETIME  TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL
);

CREATE INDEX idx_tes_audit_site ON "TES-SITE-AUDIT"(SITE_ID);
CREATE INDEX idx_tes_audit_dt ON "TES-SITE-AUDIT"(AUDIT_DATETIME DESC);

-- ---------------------------------------------------------------------
-- Tables d'agrégation HQ
-- ---------------------------------------------------------------------

-- 8. Agrégation des ventes journalières par site (HQ)
CREATE TABLE "HQ_VENTES_JOUR" (
    JOUR            DATE NOT NULL,
    SITE_ID         NUMBER NOT NULL,
    NUMTICKETS      NUMBER DEFAULT 0,
    TOTAL_HT        NUMBER(18,4) DEFAULT 0,
    TOTAL_TTC       NUMBER(18,4) DEFAULT 0,
    TOTAL_REMISE    NUMBER(18,4) DEFAULT 0,
    TOTAL_NET       NUMBER(18,4) DEFAULT 0,
    MONTANT_ESPECES NUMBER(18,4) DEFAULT 0,
    MONTANT_CB      NUMBER(18,4) DEFAULT 0,
    MONTANT_CHEQUE  NUMBER(18,4) DEFAULT 0,
    MONTANT_AUTRE   NUMBER(18,4) DEFAULT 0,
    DATCRE          DATE DEFAULT SYSDATE,
    CONSTRAINT pk_hq_ventes_jour PRIMARY KEY (JOUR, SITE_ID),
    CONSTRAINT fk_hq_ventes_site FOREIGN KEY (SITE_ID) REFERENCES "TES-SITE"(ID)
);

CREATE INDEX idx_hq_ventes_site ON "HQ_VENTES_JOUR"(SITE_ID);

-- 9. Photo stock journalier par site (HQ)
CREATE TABLE "HQ_STOCK_JOUR" (
    JOUR            DATE NOT NULL,
    SITE_ID         NUMBER NOT NULL,
    CODART          VARCHAR2(80 CHAR) NOT NULL,
    QTEPHYSIQUE     NUMBER(16,4),
    QTETHEORIQUE    NUMBER(16,4),
    VALEUR_PRMP     NUMBER(18,4),
    DATCRE          DATE DEFAULT SYSDATE,
    CONSTRAINT pk_hq_stock_jour PRIMARY KEY (JOUR, SITE_ID, CODART),
    CONSTRAINT fk_hq_stock_site FOREIGN KEY (SITE_ID) REFERENCES "TES-SITE"(ID)
);

CREATE INDEX idx_hq_stock_site_codart ON "HQ_STOCK_JOUR"(SITE_ID, CODART);

-- 10. Log de synchronisation HQ
CREATE TABLE "HQ_SYNC_LOG" (
    ID              NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    SYNC_DATETIME   TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    SITE_ID         NUMBER,
    SYNC_TYPE       VARCHAR2(50 CHAR) NOT NULL,
    SYNC_STATUS     VARCHAR2(20 CHAR) NOT NULL,
    RECORDS_PROCESSED NUMBER DEFAULT 0,
    RECORDS_FAILED  NUMBER DEFAULT 0,
    ERROR_MESSAGE   VARCHAR2(4000 CHAR),
    DETAILS         CLOB,
    CONSTRAINT fk_hq_sync_site FOREIGN KEY (SITE_ID) REFERENCES "TES-SITE"(ID)
);

CREATE INDEX idx_hq_sync_dt ON "HQ_SYNC_LOG"(SYNC_DATETIME DESC);
CREATE INDEX idx_hq_sync_status ON "HQ_SYNC_LOG"(SYNC_STATUS);

-- ---------------------------------------------------------------------
-- Séquences additionnelles (legacy compat)
-- ---------------------------------------------------------------------

CREATE SEQUENCE seq_transfer_num START WITH 1 INCREMENT BY 1 NOCACHE;

-- ---------------------------------------------------------------------
-- Triggers pour auto-numérotation
-- ---------------------------------------------------------------------

CREATE OR REPLACE TRIGGER trg_transfer_num
BEFORE INSERT ON "TES-TRANSFER"
FOR EACH ROW
WHEN (NEW.TRANSFER_NUM IS NULL)
DECLARE
    v_prefix VARCHAR2(10);
    v_seq    NUMBER;
BEGIN
    SELECT SUBSTR(SITE_CODE, 1, 3) INTO v_prefix FROM "TES-SITE" WHERE ID = :NEW.SITE_SOURCE_ID;
    :NEW.TRANSFER_NUM := v_prefix || '-' || TO_CHAR(SYSDATE, 'YYYYMMDD') || '-' || LPAD(seq_transfer_num.NEXTVAL, 5, '0');
END;
/

PROMPT
PROMPT ====================================================================
PROMPT  Schéma multi-sites créé avec succès (10 tables + 1 séquence)
PROMPT ====================================================================