# 🏪 retail-multisite-apex

Application APEX multi-site pour chaîne de supermarchés — Oracle 21c XE + APEX 26.1 + ApexLang + ORDS REST.

**1 Siège (HQ) + 1 Dépôt principal + 5 Supermarchés**, vente physique uniquement, synchro HQ via batch quotidien et ORDS REST temps réel.

---

## 🎯 En bref

| | |
|---|---|
| **Base** | Oracle 21c XE (Express Edition gratuite) |
| **Framework** | APEX 26.1 avec ApexLang (`.apx`) |
| **REST** | ORDS (Oracle REST Data Services) |
| **Pages** | 12 pages APEX (7 HQ + 5 SM) |
| **Tables** | 11 tables multi-site + 11 sites seedés |
| **Packages** | 5 packages PL/SQL |
| **Jobs** | 4 jobs DBMS_SCHEDULER |
| **Endpoints** | 7 endpoints ORDS REST |

---

## 📁 Structure du projet

```
retail-multisite-apex/
├── README.md                              ← ce fichier
├── LICENSE                                ← MIT
├── .gitignore
├── .apex/
│   └── apexlang.json                      ← version ApexLang (26.1.0+3102)
├── _apex_validate.sql                     ← script de validation
├── application.apx                        ← définition de l'app
├── page-groups.apx                        ← groupes HQ / SM
├── pages/                                 ← pages actives (renommées pNNNN-NNN.apx)
│   ├── p00000-global-page.apx
│   ├── p00100-100.apx                     ← HQ Dashboard
│   ├── p00101-101.apx                     ← Liste des Sites
│   ├── p00102-102.apx                     ← Fiche Site
│   ├── p00103-103.apx                     ← Sync Monitor
│   ├── p00104-104.apx                     ← Stock Multi-Sites
│   ├── p00105-105.apx                     ← Transferts Inter-Sites
│   ├── p00106-106.apx                     ← Ventes Agrégées
│   ├── p00200-200.apx                     ← SM Dashboard
│   ├── p00201-201.apx                     ← Stock Local
│   ├── p00202-202.apx                     ← Demande Réappro
│   ├── p00203-203.apx                     ← Transferts en Cours
│   ├── p00204-204.apx                     ← Réception Transfert
│   └── p09999-login.apx
├── shared-components/
│   ├── authentications.apx
│   ├── authorizations.apx
│   ├── breadcrumbs.apx
│   ├── build-options.apx
│   ├── component-settings.apx
│   ├── lists.apx
│   ├── static-files.apx
│   ├── static-files/icons/
│   └── themes/universal-theme/theme.apx
├── blueprints/                            ← blueprints source (SQL + variantes)
│   ├── 01_schema_multisite.sql            ← DDL 10 tables multi-site
│   ├── 02_seed_sites.sql                  ← 11 sites
│   ├── 03_sync_packages.sql               ← 3 packages PL/SQL
│   ├── 04_dbms_scheduler.sql              ← 4 jobs
│   ├── 05_authz_site_ctx.sql              ← SITE_CTX + auth functions
│   ├── 01_ords_modules_hq.sql             ← ORDS site.events (publish)
│   ├── 02_ords_modules_site.sql           ← ORDS hq.master, hq.transfers
│   ├── _deploy_all.sql                    ← Script de déploiement consolidé
│   ├── _run_deploy*.sql                   ← Scripts de connexion
│   ├── _create_ctx.sql                    ← Création contexte SITE_CTX
│   ├── p*.apx                              ← Pages source (référence)
│   ├── test_*.sql                         ← Tests E2E
│   ├── README.md
│   └── ARCHITECTURE.md
└── deployments/
    └── default.json                       ← config ApexLang
```

---

## 🚀 Démarrage rapide

### Pré-requis

- **Oracle 21c XE** ([téléchargement](https://www.oracle.com/database/technologies/appdev/xe-downloads.html))
- **APEX 26.1** déployé dans le CDB / PDB
- **SQLcl 26.2+** (pour `apexlang` CLI) ou **SQL Developer 24.x**
- **ORDS** (inclus avec XE mais à activer)

### Installation pas-à-pas

```bash
# 1. Connexion SYSDBA
sql system@localhost:1521/XEPDB1

# 2. Déploiement complet (schéma + seed + packages + scheduler + auth)
SQL> @blueprints/_deploy_all.sql

# 3. Activation ORDS + handlers
SQL> BEGIN ORDS_ADMIN.ENABLE_SCHEMA(p_schema => 'ERP_APP'); END;
/
SQL> @blueprints/01_ords_modules_hq.sql
SQL> @blueprints/02_ords_modules_site.sql

# 4. Vérification
SQL> SELECT SITE_CODE, SITE_TYPE FROM "TES-SITE" ORDER BY ID;
SQL> @blueprints/test_sync_e2e.sql
SQL> @blueprints/test_ords_sync.sql

# 5. Création du workspace APEX
# → http://localhost:8181/ords/apex_admin
#   Créer workspace ERP_WORKSPACE (parsing schema: ERP_APP)
#   Créer users APEX: admin, manager_sm1, caissier_sm1, depot_p

# 6. Câblage de l'Authentication Scheme APEX
#   Custom PL/SQL Function Returning Boolean:
#   RETURN ERP_APP.set_site_ctx_for_user(:APP_USER) IS NOT NULL;

# 7. Validation et déploiement de l'application
cd retail-multisite-apex
apexlang validate .
apexlang deploy --workspace ERP_WORKSPACE --app TES-ARTICLE --path .
```

L'application est accessible sur : `http://localhost:8181/ords/erp_workspace/tes-article/`

### Identifiants de test

| Username APEX | Site par défaut | Rôle SITE_CTX | Schéma |
|---|---|---|---|
| `admin` | HQ | HQ_ADMIN | ERP_APP |
| `manager_sm1` | SM1 | SM_MANAGER | ERP_APP |
| `caissier_sm1` | SM1 | SM_USER | ERP_APP |
| `depot_p` | DEP_P | DEPOT_USER | ERP_APP |

---

## 🔐 Authentification multi-tenant

Un mécanisme de **contexte applicatif** (`SITE_CTX`) filtre automatiquement les données par site.

Tables `TES-USER` :

| Colonne | Type | Description |
|---|---|---|
| USERNAME | VARCHAR2(100) | Login APEX |
| USER_FULLNAME | VARCHAR2(400) | Nom complet |
| EMAIL | VARCHAR2(200) | Email |
| SITE_ID | NUMBER | Site par défaut (FK TES-SITE) |
| USER_ROLE | VARCHAR2(30) | HQ_ADMIN / SM_MANAGER / SM_USER / DEPOT_USER |
| ACTIVE | VARCHAR2(1) | Y / N |

Context posé via `set_site_ctx_for_user(p_username)` à chaque requête APEX.

📌 Voir [`blueprints/05_authz_site_ctx.sql`](blueprints/05_authz_site_ctx.sql).

---

## 🌐 API REST (ORDS)

### Module `site.events` (SM → HQ)

| Endpoint | Méthode | Usage |
|---|---|---|
| `/site/events/stock/snapshot` | POST | Pousser le stock courant vers HQ |
| `/site/events/transfer/reception` | POST | Notifier HQ d'une réception |
| `/site/events/transfer/new` | POST | Demander un transfert au HQ |

### Module `hq.master` (HQ → SM, lecture)

| Endpoint | Méthode | Usage |
|---|---|---|
| `/hq/master/articles` | GET | Récupérer la liste des articles actifs |
| `/hq/master/clients` | GET | Récupérer les clients non bloqués |
| `/hq/master/fournisseurs` | GET | Articles par fournisseur principal |
| `/hq/master/promotions` | GET | Promotions actives |

### Module `hq.transfers` (HQ → sites)

| Endpoint | Méthode | Usage |
|---|---|---|
| `/hq/transfers/pending/{site_code}` | GET | Transferts en cours pour un site |
| `/hq/transfers/{id}/ship` | POST | Marquer comme expédié depuis HQ |

### Test rapide

```bash
# Vérifier le module articles
curl http://localhost:8181/ords/erp_app/hq/master/articles

# Voir les transferts en attente pour SM1
curl http://localhost:8181/ords/erp_app/hq/transfers/pending/SM1
```

---

## 🧪 Tests

### Test bout-en-bout (packages PL/SQL)

```sql
SQL> @blueprints/test_sync_e2e.sql
```

### Test pipeline ORDS

```sql
SQL> @blueprints/test_ords_sync.sql
```

---

## 🛣️ Roadmap

- [x] Architecture + schéma multi-site + seed
- [x] Packages PL/SQL + jobs scheduler + auth SITE_CTX
- [x] Pages HQ (Dashboard, Sites, Sync Monitor, Stock multi-sites, Transferts, Ventes)
- [x] Pages SM (Dashboard, Stock local, Demande réappro, Transferts cours, Réception)
- [x] ORDS REST API (publish + master data + transfers)
- [x] Tests E2E
- [ ] Authorization Schemes APEX par rôle (câblage UI)
- [ ] Module Inventaire SM (saisie comptage + reconciliation stock)
- [ ] Module Promotions HQ → push SM temps réel
- [ ] Module Rapports PDF/Excel
- [ ] Hardening prod (HTTPS, monitoring, backups RMAN)
- [ ] Tests de charge (5 SM × 100 tickets/jour)

---

## 🤝 Contribution

1. Fork le projet
2. Crée ta branche (`git checkout -b feature/ma-feature`)
3. Commit (`git commit -am 'feat: ma feature'`)
4. Push (`git push origin feature/ma-feature`)
5. Ouvre une Pull Request

---

## 📄 Licence

[MIT](LICENSE)
