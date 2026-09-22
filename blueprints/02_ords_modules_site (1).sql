-- =====================================================================
-- 02_ords_modules_site.sql
-- ORDS REST API côté HQ : endpoints GET pour consultation depuis les SM
-- + endpoints pour pousser les ordres de transfert vers les sites
-- =====================================================================

ALTER SESSION SET CURRENT_SCHEMA = ERP_APP;

-- =====================================================================
-- MODULE : hq.master
-- =====================================================================

BEGIN
    ORDS.DEFINE_MODULE(
        p_module_name    => 'hq.master',
        p_base_path      => '/hq/master/',
        p_items_per_page => 50
    );
    COMMIT;
END;
/

-- GET /hq/master/articles : récupérer la liste des articles (master data)
BEGIN
    ORDS.DEFINE_TEMPLATE(
        p_module_name => 'hq.master',
        p_pattern     => 'articles'
    );
    ORDS.DEFINE_HANDLER(
        p_module_name => 'hq.master',
        p_pattern     => 'articles',
        p_method      => 'GET',
        p_source_type => 'plsql/block',
        p_source      => '
BEGIN
    pkg_ords_api.export_articles(:cursor);
END;'
    );
    COMMIT;
END;
/

-- GET /hq/master/clients : récupérer la liste des clients
BEGIN
    ORDS.DEFINE_TEMPLATE(
        p_module_name => 'hq.master',
        p_pattern     => 'clients'
    );
    ORDS.DEFINE_HANDLER(
        p_module_name => 'hq.master',
        p_pattern     => 'clients',
        p_method      => 'GET',
        p_source_type => 'plsql/block',
        p_source      => '
BEGIN
    pkg_ords_api.export_clients(:cursor);
END;'
    );
    COMMIT;
END;
/

-- GET /hq/master/fournisseurs : récupérer la liste des fournisseurs
BEGIN
    ORDS.DEFINE_TEMPLATE(
        p_module_name => 'hq.master',
        p_pattern     => 'fournisseurs'
    );
    ORDS.DEFINE_HANDLER(
        p_module_name => 'hq.master',
        p_pattern     => 'fournisseurs',
        p_method      => 'GET',
        p_source_type => 'plsql/block',
        p_source      => '
BEGIN
    pkg_ords_api.export_fournisseurs(:cursor);
END;'
    );
    COMMIT;
END;
/

-- GET /hq/master/promotions : récupérer les promotions actives
BEGIN
    ORDS.DEFINE_TEMPLATE(
        p_module_name => 'hq.master',
        p_pattern     => 'promotions'
    );
    ORDS.DEFINE_HANDLER(
        p_module_name => 'hq.master',
        p_pattern     => 'promotions',
        p_method      => 'GET',
        p_source_type => 'plsql/block',
        p_source      => '
BEGIN
    pkg_ords_api.export_promotions(:cursor);
END;'
    );
    COMMIT;
END;
/

PROMPT Module hq.master créé

-- =====================================================================
-- MODULE : hq.transfers
-- =====================================================================

BEGIN
    ORDS.DEFINE_MODULE(
        p_module_name    => 'hq.transfers',
        p_base_path      => '/hq/transfers/',
        p_items_per_page => 50
    );
    COMMIT;
END;
/

-- GET /hq/transfers/pending/{site_code} : transferts en attente pour un site
BEGIN
    ORDS.DEFINE_TEMPLATE(
        p_module_name => 'hq.transfers',
        p_pattern     => 'pending/:site_code'
    );
    ORDS.DEFINE_HANDLER(
        p_module_name => 'hq.transfers',
        p_pattern     => 'pending/:site_code',
        p_method      => 'GET',
        p_source_type => 'plsql/block',
        p_source      => '
BEGIN
    pkg_ords_api.list_pending_for_site(:site_code, :cursor);
END;'
    );
    ORDS.DEFINE_PARAMETER(
        p_module_name => 'hq.transfers',
        p_pattern     => 'pending/:site_code',
        p_method      => 'GET',
        p_bind_variable_name => 'site_code',
        p_source_type => 'HEADER',
        p_access_method => 'IN'
    );
    COMMIT;
END;
/

-- POST /hq/transfers/{id}/ship : HQ notifie le site source que le transfert part
BEGIN
    ORDS.DEFINE_TEMPLATE(
        p_module_name => 'hq.transfers',
        p_pattern     => ':id/ship'
    );
    ORDS.DEFINE_HANDLER(
        p_module_name => 'hq.transfers',
        p_pattern     => ':id/ship',
        p_method      => 'POST',
        p_source_type => 'plsql/block',
        p_source      => '
BEGIN
    pkg_transfer.ship_transfer(:id, 1, USER);
    :status_code := 200;
    htp.p(''{"status":"SHIPPED","transfer_id":'' || :id || ''}'');
END;'
    );
    ORDS.DEFINE_PARAMETER(
        p_module_name => 'hq.transfers',
        p_pattern     => ':id/ship',
        p_method      => 'POST',
        p_bind_variable_name => 'id',
        p_source_type => 'HEADER',
        p_access_method => 'IN'
    );
    COMMIT;
END;
/

PROMPT Module hq.transfers créé

-- =====================================================================
-- Procédures d'export master data
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_ords_api_master AS
    PROCEDURE export_articles(p_cursor OUT SYS_REFCURSOR);
    PROCEDURE export_clients(p_cursor OUT SYS_REFCURSOR);
    PROCEDURE export_fournisseurs(p_cursor OUT SYS_REFCURSOR);
    PROCEDURE export_promotions(p_cursor OUT SYS_REFCURSOR);
    PROCEDURE list_pending_for_site(p_site_code IN VARCHAR2, p_cursor OUT SYS_REFCURSOR);
END;
/

CREATE OR REPLACE PACKAGE BODY pkg_ords_api_master AS

    PROCEDURE export_articles(p_cursor OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_cursor FOR
            SELECT CODART, LIBART, LIBARTR, TYPART, CODNATA,
                   CODFAM, CODSFAM, CODGRPE,
                   UNISTK, UNIACH, UNIVEN,
                   TARIFSTD, TARIFPRO, PRMP,
                   DATCRE, DATMOD
              FROM CAISSE.GCPART
             WHERE ETAT = 'A';
    END;

    PROCEDURE export_clients(p_cursor OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_cursor FOR
            SELECT CODTIE, NOMTIE, CODNATT, ADRESSE1, CPOSTAL,
                   TEL, FAX, INTERNET, NUMCONT
              FROM CAISSE.GCPTIE
             WHERE SUSP = 'N';
    END;

    PROCEDURE export_fournisseurs(p_cursor OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_cursor FOR
            SELECT s.SITE_CODE, frn.CODFRN, frn.CODART,
                   art.LIBART
              FROM CAISSE.GCPFRNART frn
              JOIN CAISSE.GCPART art ON art.CODART = frn.CODART
              JOIN "TES-SITE" s ON s.SITE_CODE = 'HQ'
             WHERE ROWNUM <= 1000;
    END;

    PROCEDURE export_promotions(p_cursor OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_cursor FOR
            SELECT CODPROMO, LIBPROMO, DDEB, DFIN, TAUXREM, ACTIVE
              FROM CAISSE.GCPROMO
             WHERE ACTIVE = 'O'
               AND DDEB <= SYSDATE
               AND DFIN >= SYSDATE;
    END;

    PROCEDURE list_pending_for_site(p_site_code IN VARCHAR2, p_cursor OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_cursor FOR
            SELECT t.TRANSFER_NUM, t.PRIORITY, t.ETAT,
                   src.SITE_CODE AS SRC, dst.SITE_CODE AS DST,
                   t.DATDEMANDE, t.DATENVOI_SOUHAITEE,
                   t.COMMENTAIRE_DEMANDE,
                   l.CODART, l.QTEDEMANDEE, l.QTEPREPAREE
              FROM "TES-TRANSFER" t
              JOIN "TES-SITE" dst ON dst.ID = t.SITE_DEST_ID
              JOIN "TES-SITE" src ON src.ID = t.SITE_SOURCE_ID
              LEFT JOIN "TES-TRANSFER-LINE" l ON l.TRANSFER_ID = t.ID
             WHERE dst.SITE_CODE = p_site_code
               AND t.ETAT IN ('VALIDE','EN_PREPARATION','EN_TRANSIT')
             ORDER BY t.PRIORITY DESC, t.DATDEMANDE;
    END;

END pkg_ords_api_master;
/

PROMPT
PROMPT ====================================================================
PROMPT  Modules ORDS HQ configurés :
PROMPT   GET  /hq/master/articles
PROMPT   GET  /hq/master/clients
PROMPT   GET  /hq/master/fournisseurs
PROMPT   GET  /hq/master/promotions
PROMPT   GET  /hq/transfers/pending/{site_code}
PROMPT   POST /hq/transfers/{id}/ship
PROMPT ====================================================================
PROMPT
PROMPT Pour tester (avec curl) :
PROMPT   curl http://localhost:8181/ords/erp_app/hq/master/articles
PROMPT   curl http://localhost:8181/ords/erp_app/hq/transfers/pending/SM1
PROMPT ====================================================================