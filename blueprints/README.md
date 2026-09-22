# Application APEX Multi-Sites — Chaîne de Supermarchés

**Stack** : Oracle 21c XE + APEX 26.1 + ApexLang + ORDS
**Périmètre** : 1 Siège (HQ) + 1 Dépôt principal + 5 Supermarchés (chacun avec dépôt de rattachement)

---

## 📁 Structure complète (Sprint 2)

```
retail_multisite/
├── ARCHITECTURE.md                              ← doc complète (schéma logique, choix de synchro)
├── README.md                                     ← ce fichier
├── deployments/
│   ├── 01_schema_multisite.sql                  ← DDL 10 tables multi-site
│   ├── 02_seed_sites.sql                        ← 11 sites (HQ + DEP_P + 5 SM + 5 DEP_SM)
│   ├── 03_sync_packages.sql                     ← 3 packages PL/SQL (multisite_core, transfer, stock)
│   ├── 04_dbms_scheduler.sql                    ← 4 jobs auto
│   └── 05_authz_site_ctx.sql                    ← auth + context + roles + users
├── pages_hq/                                     ← pages côté Siège
│   ├── p00100-hq-dashboard.apx                  ← KPIs globaux
│   ├── p00101-liste-sites.apx                   ← CRUD sites
│   ├── p00102-site-form.apx                     ← Fiche site (drawer form)
│   ├── p00103-sync-monitor.apx                  ← État synchro + logs
│   ├── p00104-stock-multisites.apx              ← Matrice stock + filtres
│   ├── p00105-transferts-inter-sites.apx        ← Vue globale transferts
│   └── p00106-ventes-aggregees.apx              ← Charts CA par site/jour
├── pages_magasin/                                ← pages côté Supermarché
│   ├── p00200-sm-dashboard.apx                  ← KPIs SM
│   ├── p00201-stock-local.apx                   ← Stock local filtré
│   ├── p00202-demande-reappro.apx               ← Demande de transfert
│   ├── p00203-transferts-cours.apx              ← Suivi transferts
│   └── p00204-reception-transfert.apx           ← Signature réception + écart
├── ords/
│   ├── 01_ords_modules_hq.sql                   ← ORDS côté site -> HQ (publish events)
│   └── 02_ords_modules_site.sql                 ← ORDS côté HQ -> sites (master data)
└── scripts/
    ├── test_sync_e2e.sql                         ← Test bout-en-bout (packages)
    └── test_ords_sync.sql                        ← Test pipeline ORDS (push stock + switch site)
```

---

## 🚀 Déploiement complet

```bash
# Étape 1 : schéma + seed
sql system@localhost:1521/XEPDB1
SQL> @deployments/01_schema_multisite.sql
SQL> @deployments/02_seed_sites.sql

# Étape 2 : packages + scheduler + auth
SQL> @deployments/03_sync_packages.sql
SQL> @deployments/04_dbms_scheduler.sql
SQL> @deployments/05_authz_site_ctx.sql

# Étape 3 : ORDS (nécessite ORDS installé)
# Pré-requis : activer le schéma ERP_APP dans ORDS :
#   BEGIN ORDS_ADMIN.ENABLE_SCHEMA(p_schema => 'ERP_APP'); END;
#   /
SQL> @ords/01_ords_modules_hq.sql
SQL> @ords/02_ords_modules_site.sql

# Étape 4 : tests
SQL> @scripts/test_sync_e2e.sql
SQL> @scripts/test_ords_sync.sql

# Étape 5 : workspace APEX (admin instance APEX)
# http://localhost:8181/ords/apex_admin
# - Créer workspace ERP_WORKSPACE (parsing schema: ERP_APP)
# - Créer users admin, manager_sm1, caissier_sm1, depot_p
# - Associer à APEX accounts

# Étape 6 : câbler l'Authentication Scheme APEX avec set_site_ctx_for_user
# (dans l'admin APEX, Authentication Scheme = Custom PL/SQL)
# Fonction : RETURN pkg_multisite_core.set_site_ctx_for_user(:APP_USER)

# Étape 7 : déployer l'application
cd /workspace/retail_multisite
apexlang validate .
apexlang deploy --workspace ERP_WORKSPACE --app ERP-MULTISITE --path .
```

---

## 🎯 Pages livrées

### Côté HQ (pages 100-199) — 7 pages

| Page | Rôle |
|---|---|
| **100** HQ Dashboard | KPIs CA jour + alertes + transferts en cours + dernière synchro + chart CA par site |
| **101** Liste des Sites | Table interactive des sites avec filtres (par groupeType) |
| **102** Site Form | Drawer pour créer/modifier un site (avec rattachement hiérarchique) |
| **103** Sync Monitor | État jobs DBMS_SCHEDULER + logs HQ_SYNC_LOG + runs Oracle + TRANSFERT en attente |
| **104** Stock Multi-Sites | Filtre site + alertes + table interactive + chart top stocks |
| **105** Transferts Inter-Sites | Filtres état/priorité + table interactive tous transferts |
| **106** Ventes Agrégées | Filtre période + line chart CA/jour + pie chart CA/site + table détail |

### Côté Supermarché (pages 200-299) — 5 pages

| Page | Rôle |
|---|---|
| **200** SM Dashboard | CA jour du site + alertes stock local + transferts attente |
| **201** Stock Local | Interactive report du stock filtré par SITE_ID + KPIs |
| **202** Demande Réappro | Form sélection articles + dépôt destinataire auto |
| **203** Transferts en Cours | 3 tables : à réceptionner / envoyés / historique récent |
| **204** Réception Transfert | Drawer signature avec écart + état + commentaire conditionnel

---

## 🔐 Authentification multi-tenant

| Élément | Rôle |
|---|---|
| `pkg_multisite_core.set_site_ctx_for_user(p_username)` | Pose SITE_CTX/SITE_ID/SITE_TYPE/USER_ROLE selon l'utilisateur |
| `pkg_multisite_core.switch_to_site(p_site_code)` | Bascule contextuel (réservé HQ_ADMIN et DEPOT_USER) |
| `is_hq_user()` | Authorization Scheme "HQ only" |
| `is_sm_or_depot_user()` | Authorization Scheme "SM access" |
| `user_can_access_site(p_site_id)` | Vérifie qu'un user peut agir sur un site donné |
| `v_current_user_ctx` | Vue pour récupérer le contexte courant |

### Users de test créés

| Username | Default site | Role |
|---|---|---|
| admin | HQ | HQ_ADMIN |
| manager_sm1 | SM1 | SM_MANAGER |
| caissier_sm1 | SM1 | SM_USER |
| depot_p | DEP_P | DEPOT_USER |

---

## 🌐 APIs ORDS REST

### Module `site.events` (côté SM → HQ)

| Endpoint | Méthode | Usage |
|---|---|---|
| `/site/events/stock/snapshot` | POST | Pousser le stock courant vers HQ |
| `/site/events/transfer/reception` | POST | Notifier HQ d'une réception |
| `/site/events/transfer/new` | POST | Demander un transfert au HQ |

### Module `hq.master` (côté HQ → SM, lecture master data)

| Endpoint | Méthode | Usage |
|---|---|---|
| `/hq/master/articles` | GET | Récupérer la liste des articles actifs |
| `/hq/master/clients` | GET | Récupérer les clients non bloqués |
| `/hq/master/fournisseurs` | GET | Articles par fournisseur principal |
| `/hq/master/promotions` | GET | Promotions actives |

### Module `hq.transfers` (côté HQ → sites)

| Endpoint | Méthode | Usage |
|---|---|---|
| `/hq/transfers/pending/{site_code}` | GET | Transferts en cours pour un site |
| `/hq/transfers/{id}/ship` | POST | Marquer comme expédié depuis HQ |

---

## 📊 Tables créées (10)

| Table | Type | Rôle |
|---|---|---|
| TES-SITE | Référentiel | 11 sites + hiérarchie parent |
| TES-MAGASIN | Référentiel | Caisses rattachées aux sites |
| TES-STOCK-SITE | Métier | Stock par site × article |
| TES-TRANSFER | Métier | Ordre de transfert (workflow 6 états) |
| TES-TRANSFER-LINE | Métier | Lignes de transfert |
| TES-TRANSFER-RECEPTION | Métier | Signature de réception + état |
| TES-SITE-AUDIT | Audit | Logs des actions multi-site |
| TES-USER | Auth | Users avec site par défaut |
| HQ_VENTES_JOUR | Agrégation | CA par jour × site |
| HQ_STOCK_JOUR | Agrégation | Photo stock par jour × site × article |
| HQ_SYNC_LOG | Agrégation | Logs des synchros HQ |

---

## 🔌 Packages PL/SQL (5)

| Package | Rôle |
|---|---|
| `pkg_multisite_core` | Contexte SITE_CTX + audit |
| `pkg_transfer` | Workflow 5 étapes (create/validate/ship/receive/cancel) |
| `pkg_stock` | Stock par site + alertes |
| `pkg_ords_api` | Handlers ORDS côté site |
| `pkg_ords_api_master` | Handlers ORDS côté HQ |

---

## 🛣️ Roadmap

| Sprint | Livrable | | Status |
|---|---|---|---|
| 0 | Architecture + schéma + seed | | ✅ |
| 1 | Packages PL/SQL + jobs scheduler | | ✅ |
| 2 | Pages HQ + SM + Auth SITE_CTX | | ✅ |
| 3 | ORDS REST API (publish + master data) | | ✅ |
| 4 | Authorization Schemes APEX par rôle | | 🔜 |
| 5 | Module Inventaire SM (saisie + reconciliation) | | 🔜 |
| 6 | Module Promotions HQ → push vers SM | | 🔜 |
| 7 | Module Rapports PDF / Excel | | 🔜 |
| 8 | Tests E2E + déploiement pilote 1 SM | | 🔜 |

---

## ⚠️ Points à valider avant prod

1. **Authentification APEX** : câbler `pkg_multisite_core.set_site_ctx_for_user` avec une Authentication Scheme APEX (PL/SQL Function Returning Boolean)
2. **HTTPS** : ORDS doit être exposé en HTTPS en production
3. **XE = 12 GB max** : surveiller le volume avec la matrice des stocks × sites
4. **Réseau entre SM et HQ** : pour la synchro temps réel (ORDS), configurer VPN site-à-site ou IP fixe
5. **JSON_TABLE** : vérifier que tu as bien Oracle 21c qui supporte JSON_TABLE (oui, depuis 12c)
6. **MV KERNEL** : le job `AGG_HQ_VENTES_DAILY` doit être étendu pour intégrer `TR_GCBRDE`, `TR_CP_ECR`, etc.

---

**Dis-moi quelle page / module tu veux prioriser ensuite** 🎯
</body>
</html>