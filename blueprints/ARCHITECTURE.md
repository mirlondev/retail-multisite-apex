# Architecture Multi-Sites — Chaîne de Supermarchés
## Oracle 21c XE + APEX 26.1 ApexLang — Synchronisation HQ

**Périmètre :**
- 1 Siège (HQ) — base centrale, master data, reporting
- 1 Dépôt principal — entrepôt central
- 5 Supermarchés — chacun avec son dépôt de rattachement
- 5 Dépôts supermarchés (dépôts intermédiaires)
- Vente physique uniquement (POS)

**Stack technique imposée :**
- Oracle Database 21c XE (Express Edition)
- APEX 26.1
- ApexLang (`.apx`)
- ORDS (Oracle REST Data Services) pour les APIs REST

---

## 1. Topologie

```
┌──────────────────────────────────────────────────────────────────────┐
│                         SIÈGE / HQ                                     │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  XEPDB1 — Schémas: ERP_APP, HQ_AGG, HQ_REPORT                   │ │
│  │  Rôle: Master data, agrégation, reporting multi-sites, pilotage│ │
│  └────────────────────────────────────────────────────────────────┘ │
│              ▲ ORDS REST API (sync site → HQ)                       │
│              │ DBMS_SCHEDULER (intégration TRANSFERT)                 │
└──────────────┼─────────────────────────────────────────────────────┘
               │
               │  (réseau IP fixe ou VPN site-à-site)
               │
       ┌───────┴────────┬─────────────┬─────────────┬─────────────┐
       │                │             │             │             │
┌──────▼──────┐ ┌───────▼─────┐ ┌────▼──────┐ ┌────▼──────┐ ┌────▼──────┐
│ Supermarché │ │Supermarché  │ │Supermarché │ │Supermarché │ │Supermarché │
│     SM1     │ │    SM2      │ │    SM3    │ │    SM4    │ │    SM5    │
│ ┌─────────┐ │ │ ┌─────────┐ │ │ ┌────────┐ │ │ ┌────────┐ │ │ ┌────────┐│
│ │POS iPad │ │ │ │POS iPad │ │ │ │POS iPad│ │ │ │POS iPad│ │ │ │POS iPad││
│ └────┬────┘ │ │ └────┬────┘ │ │ └───┬────┘ │ │ └───┬────┘ │ │ └───┬────┘│
│      │WIFI  │ │      │WIFI   │ │     │WIFI  │ │     │WIFI  │ │     │WIFI  │
│ ┌────▼────┐ │ │ ┌────▼────┐ │ │ ┌───▼────┐ │ │ ┌───▼────┐ │ │ ┌───▼────┐│
│ │APEX 26.1│ │ │ │APEX 26.1│ │ │ │APEX26.1│ │ │ │APEX26.1│ │ │ │APEX26.1││
│ │+ ORDS   │ │ │ │+ ORDS   │ │ │ │+ ORDS  │ │ │ │+ ORDS  │ │ │ │+ ORDS  ││
│ └────┬────┘ │ │ └────┬────┘ │ │ └───┬────┘ │ │ └───┬────┘ │ │ └───┬────┘│
│      │      │ │      │      │ │     │      │ │     │      │ │     │      │
│ ┌────▼────┐ │ │ ┌────▼────┐ │ │ ┌───▼────┐ │ │ ┌───▼────┐ │ │ ┌───▼────┐│
│ │Stock    │ │ │ │Stock    │ │ │ │Stock   │ │ │ │Stock   │ │ │ │Stock   ││
│ │local    │ │ │ │local    │ │ │ │local   │ │ │ │local   │ │ │ │local   ││
│ └─────────┘ │ │ └─────────┘ │ │ └────────┘ │ │ └────────┘ │ │ └────────┘│
│ + Dépôt SM1 │ │ + Dépôt SM2 │ │ + DépôtSM3 │ │ + DépôtSM4 │ │ + DépôtSM5│
└─────────────┘ └─────────────┘ └────────────┘ └────────────┘ └───────────┘

                          ▲              ▲
                          │              │
                   Livraisons    Demandes réappro
                          │              │
                   ┌──────▼──────────────▼─────┐
                   │    DÉPÔT PRINCIPAL       │
                   │    - Réception fournisseurs│
                   │    - Stock central        │
                   │    - Cross-dock           │
                   │    - APEX 26.1 + ORDS     │
                   └──────────────────────────┘
```

---

## 2. Modèle de données multi-site

### Principe : **une seule base XE 21c, sites logiques séparés par SITE_ID**

Vu que tu es en XE (limite 12 GB, 1 instance), on ne peut pas se permettre une base par site. On utilise donc :

- **Schémas existants** : `CAISSE`, `CASH`, `XCPTA`, `KERNEL` — **données locales du site**
- **Schéma `TRANSFERT`** — **buffer de synchro** (existant déjà, on l'étend)
- **Nouveau schéma `HQ_AGG`** — **agrégation HQ** des données multi-sites
- **Schéma `ERP_APP`** — couche APEX existante

### Tables à ajouter

| Table | Rôle | Qui l'utilise |
|---|---|---|
| `TES-SITE` | Référentiel des sites (HQ, Dépôt, SM1-5) | Tous |
| `TES-MAGASIN` | Magasins rattachés à un dépôt | Tous |
| `TES-STOCK-SITE` | Stock par site / article | Tous |
| `TES-TRANSFER` | Ordre de transfert entre sites | Magasin → Dépôt |
| `TES-TRANSFER-LINE` | Lignes de transfert | Magasin |
| `TES-TRANSFER-RECEPTION` | Réception (signée) d'un transfert | Magasin |
| `HQ_VENTES_JOUR` | Agrégation ventes journalières (HQ) | HQ |
| `HQ_STOCK_JOUR` | Agrégation stock journalier (HQ) | HQ |
| `HQ_SYNC_LOG` | Audit de la synchro TRANSFERT | HQ |

---

## 3. Stratégie de synchronisation

### Deux modes complémentaires

#### Mode A — **Synchro batch quotidienne** (déjà en place via `TRANSFERT`)

```
[Site SM1]                       [HQ]
  CAISSE.*                        HQ_AGG.*
     │                              ▲
     ▼ (triggers)                   │
  TRANSFERT.TR_*  ──[23h00]──►     │
     │                    job      │
     └─► flag "synced=1"           │
                                    ▼
                              Intégration dans
                              HQ_VENTES_JOUR
```

**Avantage :** fonctionne même si le réseau est intermittent, pas de contrainte temps réel.
**Inconvénient :** le siège a J-1 au mieux.

#### Mode B — **APIs REST ORDS temps réel** (pour le stock et les transferts)

```
SM1 (ORDS) --POST /stock/level--> HQ (ORDS handler)
SM1 (ORDS) --POST /transfer/new--> HQ (ORDS handler)
```

**Avantage :** visibilité temps réel.
**Inconvénient :** nécessite connectivité permanente.

➡️ **Recommandation :** Mode A pour les ventes/compta (batch), Mode B pour les transferts et alertes stock (temps réel).

---

## 4. Schéma relationnel multi-site

```
TES-SITE
─────────
SITE_ID (PK)
SITE_CODE (ex: HQ, DEP_P, SM1, DEP_SM1)
SITE_NAME
SITE_TYPE (HEAD_OFFICE / DEPOT / DEPOT_SM / SUPERMARKET)
PARENT_SITE_ID (FK → TES-SITE, NULL pour HQ)
ADDRESS
CITY
PHONE
EMAIL
ACTIVE (Y/N)
DATCRE, DATMOD

TES-MAGASIN
────────────
MAGASIN_ID (PK)
SITE_ID (FK → TES-SITE)
MAGASIN_NAME
MAGASIN_TYPE (PRINCIPAL / ANNEXE)
CASHIER_COUNT
POS_COUNT
ACTIVE

TES-STOCK-SITE
──────────────
STOCK_SITE_ID (PK)
SITE_ID (FK → TES-SITE)
CODART
QTEPHYSIQUE       (stock réel après inventaire)
QTETHEORIQUE      (stock système après MV)
QTEMIN
QTEMAX
DERNIER_MVT_DATE
DATCRE, DATMOD

TES-TRANSFER (ordre de transfert)
──────────────────────────────────
TRANSFER_ID (PK)
TRANSFER_NUM  (numéro séquentiel)
SITE_SOURCE_ID (FK → TES-SITE)
SITE_DEST_ID   (FK → TES-SITE)
DATTRANSFER (date demande)
DATENVOI (date départ prévue)
DATRECEPTION (date réception prévue)
ETAT (DEMANDE / EN_PREPARATION / EN_TRANSIT / RECEPTIONNE / CLOTURE / ANNULE)
PRIORITY (NORMALE / URGENTE)
COMMENTAIRE
CUTI (utilisateur demandeur)
DATCRE, DATMOD

TES-TRANSFER-LINE
─────────────────
TRANSFER_LINE_ID (PK)
TRANSFER_ID (FK → TES-TRANSFER)
CODART
QTEDEMANDEE
QTEEXPEDIEE
QTERECEPTIONNEE
PRIX_UNITAIRE
COMMENTAIRE

TES-TRANSFER-RECEPTION
──────────────────────
RECEPTION_ID (PK)
TRANSFER_ID (FK)
DATRECEPTION_EFFECTIVE
RECEPTIONNE_PAR (utilisateur)
COMMENTAIRE_RECEPTION
ETAT_RECEPTION (CONFORME / PARTIELLE / NON_CONFORME)

HQ_VENTES_JOUR (agrégation HQ)
──────────────────────────────
JOUR (PK)
SITE_ID (FK)
NUMTICKETS (count)
TOTAL_HT
TOTAL_TTC
TOTAL_REMISE
TOTAL_NET
MONTANT_ESPECES
MONTANT_CB
MONTANT_CHEQUE
MONTANT_AUTRE
DATCRE

HQ_STOCK_JOUR (photo stock journalier HQ)
─────────────────────────────────────────
JOUR (PK)
SITE_ID (FK)
CODART (PK combiné avec JOUR+SITE_ID)
QTEPHYSIQUE
QTETHEORIQUE
VALEUR_PRMP

HQ_SYNC_LOG
───────────
SYNC_ID (PK)
SITE_ID (FK)
SYNC_TYPE (TRANSFERT_INTEGRATION / REST_POST / ORDS_RECEIVED)
SYNC_STATUS (SUCCESS / FAILED / WARNING)
SYNC_DATETIME
RECORDS_PROCESSED
ERROR_MESSAGE
```

---

## 5. Rôles et écrans APEX

### Côté Siège (HQ) — `pages_hq/`

| Page | Titre | Rôle |
|---|---|---|
| 100 | HQ Dashboard | KPIs multi-sites, CA total, alertes |
| 101 | Liste des sites | Admin sites (CRUD) |
| 102 | Magasins | Liste des magasins rattachés à leur dépôt |
| 103 | Sync Monitor | État TRANSFERT, fichiers en attente, erreurs |
| 104 | Stock multi-sites | Vue agrégée stock par site et par article |
| 105 | Transferts inter-sites | Demandes, expéditions, réceptions |
| 106 | Ventes agrégées | CA par site / jour / mois |
| 107 | Alertes stock | Articles sous le seuil, ruptures |
| 108 | Audit synchro | Log des synchros HQ → site |

### Côté Supermarché — `pages_magasin/`

| Page | Titre | Rôle |
|---|---|---|
| 200 | SM Dashboard | KPI du jour, alertes locales |
| 201 | Stock local | Stock du supermarché (TES-STOCK-SITE filtré par SITE_ID) |
| 202 | Demande réappro | Bouton "Demander transfert au dépôt" |
| 203 | Transferts en cours | Suivi des transferts demandés / reçus |
| 204 | Réception transfert | Signer la réception, signaler écart |
| 205 | Ventes du jour | Rapports J+0 du supermarché |
| 206 | Inventaire | Saisie inventaire (alimente TES-STOCK-SITE) |

### Côté Dépôt — `pages_depot/` (bonus)

| Page | Titre | Rôle |
|---|---|---|
| 300 | Dépôt Dashboard | Stock central, préparation transferts |
| 301 | Stock dépôt | Stock à dispatcher |
| 302 | Préparation transfert | Picking, validation, génération bordereau |

---

## 6. Jobs de synchronisation

### Côté supermarché (chaque site)

```sql
-- Job 1 : Push des ventes vers TRANSFERT (déjà existant)
DBMS_SCHEDULER.CREATE_JOB (
   job_name   => 'PUSH_VENTES_TO_TRANSFERT',
   job_type   => 'PLSQL_BLOCK',
   job_action => 'BEGIN push_ventes_to_transfert; END;',
   repeat_interval => 'FREQ=HOURLY',
   enabled   => TRUE);

-- Job 2 : POST au HQ via ORDS (nouveau)
DBMS_SCHEDULER.CREATE_JOB (
   job_name   => 'POST_STOCK_TO_HQ',
   job_type   => 'PLSQL_BLOCK',
   job_action => 'BEGIN post_stock_levels_to_hq; END;',
   repeat_interval => 'FREQ=MINUTELY;INTERVAL=15',
   enabled   => TRUE);

-- Job 3 : réception des transferts HQ
DBMS_SCHEDULER.CREATE_JOB (
   job_name   => 'PULL_TRANSFER_FROM_HQ',
   job_type   => 'PLSQL_BLOCK',
   job_action => 'BEGIN pull_transfers_from_hq; END;',
   repeat_interval => 'FREQ=MINUTELY;INTERVAL=10',
   enabled   => TRUE);
```

### Côté HQ

```sql
-- Job 4 : intégration des TRANSFERT reçus
DBMS_SCHEDULER.CREATE_JOB (
   job_name   => 'INTEGRATE_TRANSFERT',
   job_type   => 'PLSQL_BLOCK',
   job_action => 'BEGIN integrate_transfert_buffer; END;',
   repeat_interval => 'FREQ=DAILY;BYHOUR=23;BYMINUTE=30',
   enabled   => TRUE);

-- Job 5 : agrégation ventes journalières HQ
DBMS_SCHEDULER.CREATE_JOB (
   job_name   => 'AGGREGATE_HQ_VENTES',
   job_type   => 'PLSQL_BLOCK',
   job_action => 'BEGIN aggregate_hq_ventes_jour; END;',
   repeat_interval => 'FREQ=DAILY;BYHOUR=0;BYMINUTE=30',
   enabled   => TRUE);

-- Job 6 : calcul stocks HQ (à partir des snapshots par site)
DBMS_SCHEDULER.CREATE_JOB (
   job_name   => 'CALCULATE_HQ_STOCK',
   job_type   => 'PLSQL_BLOCK',
   job_action => 'BEGIN calculate_hq_stock_jour; END;',
   repeat_interval => 'FREQ=DAILY;BYHOUR=1;BYMINUTE=0',
   enabled   => TRUE);
```

---

## 7. Sécurité / multi-tenant

Comme on a **une seule base XE** partagée entre tous les sites, on sépare les données par `SITE_ID` et on utilise des **contextes applicatifs APEX** :

```sql
-- Contexte de session pour filtrer par site
CREATE CONTEXT site_ctx USING site_context_pkg;

CREATE OR REPLACE PACKAGE site_context_pkg AS
   PROCEDURE set_site(p_site_id IN NUMBER);
   FUNCTION current_site RETURN NUMBER;
END;
/

-- Trigger pour forcer le SITE_ID sur les insertions
CREATE OR REPLACE TRIGGER trg_stock_site_siteid
BEFORE INSERT ON TES-STOCK-SITE
FOR EACH ROW
BEGIN
   :NEW.SITE_ID := site_context_pkg.current_site;
END;
/
```

Côté APEX, chaque utilisateur (caissier, manager, acheteur HQ) a un **SITE_ID par défaut** dans la table `KERNEL.UTUTI` ou via une `AUTHORIZATION SCHEME`.

---

## 8. Limites XE à surveiller

| Limite XE 21c | Valeur | Impact pour toi |
|---|---|---|
| Données utilisateur | 12 GB | ⚠️ 5 supermarchés actifs + HQ + stock peuvent atteindre la limite |
| CPU | 2 | ⚠️ En heures de pointe (caisse), risque de contention |
| RAM | 2 GB | OK pour le POS, serré pour reporting HQ |
| Tablespaces | Pas de Bigfile | Utiliser autoextend sur tous les TS |
| Partitionnement | ❌ indisponible | Les MV KERNEL restent en heap classique |

**Recommandation** : surveiller `DBA_FREE_SPACE` et `DBA_TABLESPACE_USAGE_METRICS`, mettre en place **archivage annuel** (commande `delete from` sur les tables d'archive > 2 ans).

---

## 9. Déploiement en 8 étapes

```bash
# Étape 1 — Schéma multi-site
sql system@localhost:1521/XEPDB1
SQL> @deployments/01_schema_multisite.sql
SQL> @deployments/02_seed_sites.sql        -- 5 SM + 5 dépôts + HQ + dépôt principal

# Étape 2 — Procédures de synchro
SQL> @deployments/03_sync_packages.sql     -- PL/SQL packages de sync
SQL> @deployments/04_dbms_scheduler.sql    -- Jobs automatiques

# Étape 3 — ORDS (REST APIs)
SQL> @ords/01_ords_modules_hq.sql          -- HQ endpoints
SQL> @ords/02_ords_modules_site.sql        -- Site endpoints

# Étape 4 — Sécurité multi-tenant
SQL> @deployments/05_context_security.sql

# Étape 5 — Données initiales
SQL> @deployments/06_init_data.sql

# Étape 6 — Workspace APEX (admin instance)
# http://localhost:8181/ords/apex_admin
# Create workspace ERP_WORKSPACE (parsing schema: ERP_APP)

# Étape 7 — Déployer l'app
cd /workspace/retail_multisite
apexlang validate .
apexlang deploy --workspace ERP_WORKSPACE --app ERP-MULTISITE --path .

# Étape 8 — Tester la synchro
SQL> @scripts/test_sync_e2e.sql
```

---

## 10. Roadmap

| Sprint | Durée | Livrable |
|---|---|---|
| Sprint 0 | 1 sem | Schéma `TES-SITE`, seed, première page HQ Dashboard |
| Sprint 1 | 2 sem | Module transfert entrepôt → magasin (5 pages) |
| Sprint 2 | 2 sem | Module stock multi-sites + alertes |
| Sprint 3 | 2 sem | Module ventes agrégées + reporting HQ |
| Sprint 4 | 2 sem | ORDS REST + synchro temps réel stock |
| Sprint 5 | 2 sem | Tests E2E, mise en production pilote (1 SM) |
| Sprint 6 | 2 sem | Roll-out sur les 4 autres SM |

---

**Suite logique :** on commence par quoi ? Je te propose de coder les **fichiers dans l'ordre** suivant :
1. `01_schema_multisite.sql` (DDL pur)
2. `02_seed_sites.sql` (insert des 11 sites)
3. `pages_hq/p00100-hq-dashboard.apx` (premier écran)
4. `pages_magasin/p00200-sm-dashboard.apx` (côté SM)

Dis-moi 🎯