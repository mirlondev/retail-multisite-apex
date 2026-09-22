-- =====================================================================
-- 03_sync_packages.sql
-- Packages PL/SQL pour la synchronisation multi-sites
-- =====================================================================

ALTER SESSION SET CURRENT_SCHEMA = ERP_APP;

-- ---------------------------------------------------------------------
-- Package : pkg_multisite_core
-- Fonctions utilitaires multi-site
-- ---------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_multisite_core AS

    -- Récupérer le SITE_ID courant (depuis contexte applicatif)
    FUNCTION current_site RETURN NUMBER;

    -- Récupérer le code du site courant
    FUNCTION current_site_code RETURN VARCHAR2;

    -- Récupérer le type du site
    FUNCTION current_site_type RETURN VARCHAR2;

    -- Vérifier qu'un site existe
    FUNCTION site_exists(p_site_code IN VARCHAR2) RETURN BOOLEAN;

    -- Récupérer l'ID d'un site à partir de son code
    FUNCTION get_site_id(p_site_code IN VARCHAR2) RETURN NUMBER;

    -- Récupérer le parent (dépôt rattaché) d'un supermarché
    FUNCTION get_parent_site(p_site_id IN NUMBER) RETURN NUMBER;

    -- Logger une action dans l'audit
    PROCEDURE log_action(
        p_site_id      IN NUMBER,
        p_audit_type   IN VARCHAR2,
        p_entity_table IN VARCHAR2 DEFAULT NULL,
        p_entity_id    IN NUMBER DEFAULT NULL,
        p_action       IN VARCHAR2 DEFAULT NULL,
        p_user         IN VARCHAR2 DEFAULT USER,
        p_details      IN VARCHAR2 DEFAULT NULL
    );

END pkg_multisite_core;
/

CREATE OR REPLACE PACKAGE BODY pkg_multisite_core AS

    g_default_site_id NUMBER;

    FUNCTION current_site RETURN NUMBER IS
    BEGIN
        RETURN NVL(SYS_CONTEXT('SITE_CTX', 'SITE_ID'), g_default_site_id);
    END;

    FUNCTION current_site_code RETURN VARCHAR2 IS
    BEGIN
        RETURN SYS_CONTEXT('SITE_CTX', 'SITE_CODE');
    END;

    FUNCTION current_site_type RETURN VARCHAR2 IS
    BEGIN
        RETURN SYS_CONTEXT('SITE_CTX', 'SITE_TYPE');
    END;

    FUNCTION site_exists(p_site_code IN VARCHAR2) RETURN BOOLEAN IS
        v_count NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_count FROM "TES-SITE" WHERE SITE_CODE = p_site_code AND ACTIVE='Y';
        RETURN v_count > 0;
    END;

    FUNCTION get_site_id(p_site_code IN VARCHAR2) RETURN NUMBER IS
        v_id NUMBER;
    BEGIN
        SELECT ID INTO v_id FROM "TES-SITE" WHERE SITE_CODE = p_site_code;
        RETURN v_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN NULL;
    END;

    FUNCTION get_parent_site(p_site_id IN NUMBER) RETURN NUMBER IS
        v_parent_id NUMBER;
    BEGIN
        SELECT PARENT_SITE_ID INTO v_parent_id FROM "TES-SITE" WHERE ID = p_site_id;
        RETURN v_parent_id;
    END;

    PROCEDURE log_action(
        p_site_id      IN NUMBER,
        p_audit_type   IN VARCHAR2,
        p_entity_table IN VARCHAR2 DEFAULT NULL,
        p_entity_id    IN NUMBER DEFAULT NULL,
        p_action       IN VARCHAR2 DEFAULT NULL,
        p_user         IN VARCHAR2 DEFAULT USER,
        p_details      IN VARCHAR2 DEFAULT NULL
    ) IS
    BEGIN
        INSERT INTO "TES-SITE-AUDIT"
            (SITE_ID, AUDIT_TYPE, ENTITY_TABLE, ENTITY_ID, ACTION, USER_NAME, DETAILS)
        VALUES
            (p_site_id, p_audit_type, p_entity_table, p_entity_id, p_action, p_user, p_details);
        COMMIT;
    END;

END pkg_multisite_core;
/

-- Contexte applicatif
CREATE CONTEXT site_ctx USING pkg_multisite_core;

PROMPT Package pkg_multisite_core créé


-- ---------------------------------------------------------------------
-- Package : pkg_transfer
-- Gestion des transferts inter-sites
-- ---------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_transfer AS

    -- Créer une demande de transfert
    PROCEDURE create_transfer(
        p_site_dest_code  IN VARCHAR2,
        p_priority        IN VARCHAR2 DEFAULT 'NORMALE',
        p_date_souhaitee  IN DATE DEFAULT NULL,
        p_commentaire     IN VARCHAR2 DEFAULT NULL,
        p_lignes          IN t_lignes_tab,
        p_transfer_id     OUT NUMBER,
        p_transfer_num    OUT VARCHAR2
    );

    -- Valider une demande (passage en EN_PREPARATION)
    PROCEDURE validate_transfer(p_transfer_id IN NUMBER);

    -- Démarrer l'expédition (passage en EN_TRANSIT)
    PROCEDURE ship_transfer(
        p_transfer_id IN NUMBER,
        p_colis       IN NUMBER DEFAULT 1,
        p_cuti_envoi  IN VARCHAR2 DEFAULT USER
    );

    -- Réceptionner (passage en RECEPTIONNE)
    PROCEDURE receive_transfer(
        p_transfer_id     IN NUMBER,
        p_receptionne_par IN VARCHAR2,
        p_etat_reception  IN VARCHAR2 DEFAULT 'CONFORME',
        p_colis_attendus  IN NUMBER,
        p_colis_recus     IN NUMBER,
        p_commentaire     IN VARCHAR2 DEFAULT NULL
    );

    -- Annuler un transfert
    PROCEDURE cancel_transfer(p_transfer_id IN NUMBER, p_motif IN VARCHAR2);

    -- Lister les transferts en cours pour le site courant
    FUNCTION list_pending_transfers(p_site_id IN NUMBER) RETURN SYS_REFCURSOR;

    TYPE t_lignes_tab IS TABLE OF t_ligne_rec;
    TYPE t_ligne_rec IS RECORD (
        codart        VARCHAR2(80),
        qte           NUMBER,
        prix_unitaire NUMBER
    );

END pkg_transfer;
/

CREATE OR REPLACE PACKAGE BODY pkg_transfer AS

    PROCEDURE create_transfer(
        p_site_dest_code  IN VARCHAR2,
        p_priority        IN VARCHAR2 DEFAULT 'NORMALE',
        p_date_souhaitee  IN DATE DEFAULT NULL,
        p_commentaire     IN VARCHAR2 DEFAULT NULL,
        p_lignes          IN t_lignes_tab,
        p_transfer_id     OUT NUMBER,
        p_transfer_num    OUT VARCHAR2
    ) IS
        v_site_source_id NUMBER := pkg_multisite_core.current_site;
        v_site_dest_id   NUMBER := pkg_multisite_core.get_site_id(p_site_dest_code);
        v_numlig         NUMBER := 0;
    BEGIN
        IF v_site_source_id IS NULL THEN
            RAISE_APPLICATION_ERROR(-20001, 'Pas de SITE_ID courant dans le contexte');
        END IF;
        IF v_site_dest_id IS NULL THEN
            RAISE_APPLICATION_ERROR(-20002, 'Site destination ' || p_site_dest_code || ' introuvable');
        END IF;
        IF v_site_source_id = v_site_dest_id THEN
            RAISE_APPLICATION_ERROR(-20003, 'Source et destination identiques');
        END IF;

        INSERT INTO "TES-TRANSFER"
            (SITE_SOURCE_ID, SITE_DEST_ID, DATENVOI_SOUHAITEE, ETAT, PRIORITY, COMMENTAIRE_DEMANDE, CUTI_DEMANDE)
        VALUES
            (v_site_source_id, v_site_dest_id, p_date_souhaitee, 'DEMANDE', p_priority, p_commentaire, USER)
        RETURNING ID, TRANSFER_NUM INTO p_transfer_id, p_transfer_num;

        FOR i IN 1..p_lignes.COUNT LOOP
            v_numlig := v_numlig + 10;
            INSERT INTO "TES-TRANSFER-LINE"
                (TRANSFER_ID, NUMLIG, CODART, QTEDEMANDEE, PRIX_UNITAIRE)
            VALUES
                (p_transfer_id, v_numlig, p_lignes(i).codart, p_lignes(i).qte, p_lignes(i).prix_unitaire);
        END LOOP;

        pkg_multisite_core.log_action(
            p_site_id      => v_site_source_id,
            p_audit_type   => 'TRANSFER_CREATED',
            p_entity_table => 'TES-TRANSFER',
            p_entity_id    => p_transfer_id,
            p_action       => 'CREATE',
            p_details      => 'Transfert vers ' || p_site_dest_code || ' (' || p_lignes.COUNT || ' lignes)'
        );

        COMMIT;
    END;

    PROCEDURE validate_transfer(p_transfer_id IN NUMBER) IS
    BEGIN
        UPDATE "TES-TRANSFER" SET ETAT='EN_PREPARATION', DATMOD=SYSDATE WHERE ID=p_transfer_id AND ETAT='DEMANDE';
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20010, 'Transfert ' || p_transfer_id || ' non trouvé ou déjà validé');
        END IF;
        pkg_multisite_core.log_action(NULL, 'TRANSFER_VALIDATED', 'TES-TRANSFER', p_transfer_id, 'UPDATE');
        COMMIT;
    END;

    PROCEDURE ship_transfer(
        p_transfer_id IN NUMBER,
        p_colis       IN NUMBER DEFAULT 1,
        p_cuti_envoi  IN VARCHAR2 DEFAULT USER
    ) IS
    BEGIN
        UPDATE "TES-TRANSFER"
           SET ETAT='EN_TRANSIT',
               DATENVOI_EFFECTIVE=SYSDATE,
               NB_COLIS_ENVOYES=p_colis,
               CUTI_ENVOI=p_cuti_envoi,
               DATMOD=SYSDATE
         WHERE ID=p_transfer_id AND ETAT='EN_PREPARATION';
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20011, 'Transfert ' || p_transfer_id || ' non trouvé ou pas en préparation');
        END IF;
        -- Débiter le stock source sur chaque ligne
        UPDATE "TES-TRANSFER-LINE"
           SET QTEEXPEDIEE = QTEDEMANDEE
         WHERE TRANSFER_ID = p_transfer_id;

        -- Débiter le stock site source (et incrémenter le transit)
        FOR r IN (
            SELECT CODART, QTEDEMANDEE
              FROM "TES-TRANSFER-LINE"
             WHERE TRANSFER_ID = p_transfer_id
        ) LOOP
            UPDATE "TES-STOCK-SITE"
               SET QTETHEORIQUE = QTETHEORIQUE - r.QTEDEMANDEE,
                   QTEENTRANSIT = NVL(QTEENTRANSIT, 0),  -- ne pas incrémenter ici, c'est le transit ENVERS le site
                   DATMOD = SYSDATE
             WHERE SITE_ID = pkg_multisite_core.current_site
               AND CODART = r.CODART;
        END LOOP;

        pkg_multisite_core.log_action(NULL, 'TRANSFER_SHIPPED', 'TES-TRANSFER', p_transfer_id, 'UPDATE');
        COMMIT;
    END;

    PROCEDURE receive_transfer(
        p_transfer_id     IN NUMBER,
        p_receptionne_par IN VARCHAR2,
        p_etat_reception  IN VARCHAR2 DEFAULT 'CONFORME',
        p_colis_attendus  IN NUMBER,
        p_colis_recus     IN NUMBER,
        p_commentaire     IN VARCHAR2 DEFAULT NULL
    ) IS
        v_site_dest_id NUMBER;
    BEGIN
        SELECT SITE_DEST_ID INTO v_site_dest_id FROM "TES-TRANSFER" WHERE ID = p_transfer_id;

        UPDATE "TES-TRANSFER"
           SET ETAT='RECEPTIONNE',
               DATRECEPT_EFFECTIVE=SYSDATE,
               CUTI_RECEPT=p_receptionne_par,
               COMMENTAIRE_RECEPT=p_commentaire,
               DATMOD=SYSDATE
         WHERE ID=p_transfer_id AND ETAT='EN_TRANSIT';
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20012, 'Transfert ' || p_transfer_id || ' non trouvé ou pas en transit');
        END IF;

        INSERT INTO "TES-TRANSFER-RECEPTION"
            (TRANSFER_ID, DATRECEPTION, RECEPTIONNE_PAR, ETAT_RECEPTION,
             NB_COLIS_ATTENDUS, NB_COLIS_RECUS, COMMENTAIRE)
        VALUES
            (p_transfer_id, SYSDATE, p_receptionne_par, p_etat_reception,
             p_colis_attendus, p_colis_recus, p_commentaire);

        -- Créditer le stock site destination
        FOR r IN (
            SELECT CODART, QTEDEMANDEE
              FROM "TES-TRANSFER-LINE"
             WHERE TRANSFER_ID = p_transfer_id
        ) LOOP
            MERGE INTO "TES-STOCK-SITE" t
            USING (SELECT v_site_dest_id AS SITE_ID, r.CODART AS CODART,
                          r.QTEDEMANDEE AS QTE FROM DUAL) s
            ON (t.SITE_ID = s.SITE_ID AND t.CODART = s.CODART)
            WHEN MATCHED THEN UPDATE SET
                QTETHEORIQUE = t.QTETHEORIQUE + s.QTE,
                QTEENTRANSIT = NVL(t.QTEENTRANSIT,0) - s.QTE,
                DERNIER_MVT = SYSDATE,
                DATMOD = SYSDATE
            WHEN NOT MATCHED THEN INSERT (SITE_ID, CODART, QTETHEORIQUE, DERNIER_MVT)
            VALUES (s.SITE_ID, s.CODART, s.QTE, SYSDATE);
        END LOOP;

        pkg_multisite_core.log_action(
            v_site_dest_id, 'TRANSFER_RECEIVED', 'TES-TRANSFER', p_transfer_id, 'UPDATE',
            p_receptionne_par, p_commentaire);
        COMMIT;
    END;

    PROCEDURE cancel_transfer(p_transfer_id IN NUMBER, p_motif IN VARCHAR2) IS
    BEGIN
        UPDATE "TES-TRANSFER"
           SET ETAT='ANNULE',
               COMMENTAIRE_DEMANDE = COMMENTAIRE_DEMANDE || ' [ANNULE: ' || p_motif || ']',
               DATMOD=SYSDATE
         WHERE ID=p_transfer_id AND ETAT IN ('DEMANDE','VALIDE','EN_PREPARATION');
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20013, 'Transfert ' || p_transfer_id || ' non annulable');
        END IF;
        COMMIT;
    END;

    FUNCTION list_pending_transfers(p_site_id IN NUMBER) RETURN SYS_REFCURSOR IS
        v_rc SYS_REFCURSOR;
    BEGIN
        OPEN v_rc FOR
            SELECT t.ID, t.TRANSFER_NUM, src.SITE_CODE AS SITE_SOURCE,
                   dst.SITE_CODE AS SITE_DEST, t.ETAT, t.PRIORITY,
                   t.DATDEMANDE, t.DATENVOI_SOUHAITEE,
                   (SELECT COUNT(*) FROM "TES-TRANSFER-LINE" l WHERE l.TRANSFER_ID=t.ID) AS NB_LIGNES
              FROM "TES-TRANSFER" t
              JOIN "TES-SITE" src ON src.ID = t.SITE_SOURCE_ID
              JOIN "TES-SITE" dst ON dst.ID = t.SITE_DEST_ID
             WHERE (t.SITE_SOURCE_ID = p_site_id OR t.SITE_DEST_ID = p_site_id)
               AND t.ETAT NOT IN ('RECEPTIONNE','CLOTURE','ANNULE')
             ORDER BY t.PRIORITY DESC, t.DATDEMANDE DESC;
        RETURN v_rc;
    END;

END pkg_transfer;
/

PROMPT Package pkg_transfer créé


-- ---------------------------------------------------------------------
-- Package : pkg_stock
-- Gestion du stock par site
-- ---------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_stock AS

    -- Ajuster le stock physique (inventaire)
    PROCEDURE set_physical_stock(
        p_site_id IN NUMBER,
        p_codart  IN VARCHAR2,
        p_qte     IN NUMBER
    );

    -- Récupérer le stock disponible pour transfert
    FUNCTION get_available_stock(p_site_id IN NUMBER, p_codart IN VARCHAR2) RETURN NUMBER;

    -- Liste des articles en alerte stock
    FUNCTION list_low_stock(p_site_id IN NUMBER) RETURN SYS_REFCURSOR;

END pkg_stock;
/

CREATE OR REPLACE PACKAGE BODY pkg_stock AS

    PROCEDURE set_physical_stock(
        p_site_id IN NUMBER,
        p_codart  IN VARCHAR2,
        p_qte     IN NUMBER
    ) IS
    BEGIN
        MERGE INTO "TES-STOCK-SITE" t
        USING (SELECT p_site_id AS SITE_ID, p_codart AS CODART, p_qte AS QTE FROM DUAL) s
        ON (t.SITE_ID = s.SITE_ID AND t.CODART = s.CODART)
        WHEN MATCHED THEN UPDATE SET
            QTEPHYSIQUE = s.QTE,
            DERNIER_MVT = SYSDATE,
            DATMOD = SYSDATE
        WHEN NOT MATCHED THEN INSERT (SITE_ID, CODART, QTEPHYSIQUE, QTETHEORIQUE, DERNIER_MVT)
        VALUES (s.SITE_ID, s.CODART, s.QTE, s.QTE, SYSDATE);

        pkg_multisite_core.log_action(
            p_site_id, 'STOCK_ADJUSTED', 'TES-STOCK-SITE', NULL, 'UPDATE',
            USER, 'Article ' || p_codart || ' = ' || p_qte);
        COMMIT;
    END;

    FUNCTION get_available_stock(p_site_id IN NUMBER, p_codart IN VARCHAR2) RETURN NUMBER IS
        v_qte NUMBER;
    BEGIN
        SELECT NVL(QTETHEORIQUE,0) - NVL(QTEENTRANSIT,0) - NVL(QTECOMMANDE,0)
          INTO v_qte
          FROM "TES-STOCK-SITE"
         WHERE SITE_ID = p_site_id AND CODART = p_codart;
        RETURN NVL(v_qte, 0);
    END;

    FUNCTION list_low_stock(p_site_id IN NUMBER) RETURN SYS_REFCURSOR IS
        v_rc SYS_REFCURSOR;
    BEGIN
        OPEN v_rc FOR
            SELECT s.SITE_ID, si.SITE_CODE, s.CODART,
                   p.LIBART, p.LIBARTR,
                   s.QTEPHYSIQUE, s.QTETHEORIQUE,
                   s.QTEMIN, s.QTESEC,
                   CASE WHEN NVL(s.QTEPHYSIQUE,0) <= 0 THEN 'RUPTURE'
                        WHEN NVL(s.QTEPHYSIQUE,0) <= NVL(s.QTEMIN,0) THEN 'CRITIQUE'
                        WHEN NVL(s.QTEPHYSIQUE,0) <= NVL(s.QTESEC,0) THEN 'BAS'
                        ELSE 'OK' END AS ALERTE
              FROM "TES-STOCK-SITE" s
              JOIN "TES-SITE" si ON si.ID = s.SITE_ID
              LEFT JOIN CAISSE.GCPART p ON p.CODART = s.CODART
             WHERE s.SITE_ID = p_site_id
               AND NVL(s.QTEPHYSIQUE,0) <= NVL(s.QTEMIN, NVL(s.QTESEC,0))
             ORDER BY s.QTEPHYSIQUE ASC;
        RETURN v_rc;
    END;

END pkg_stock;
/

PROMPT Package pkg_stock créé

PROMPT
PROMPT ====================================================================
PROMPT  Tous les packages PL/SQL installés :
PROMPT   - pkg_multisite_core : utilitaires + audit + contexte
PROMPT   - pkg_transfer : gestion des transferts inter-sites
PROMPT   - pkg_stock : stock par site + alertes
PROMPT ====================================================================