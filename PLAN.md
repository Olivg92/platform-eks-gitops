# Plan du portfolio DevOps / SRE / Platform Engineer

Objectif : prouver deux choses à un recruteur.
1. Je sais construire une plateforme de bout en bout (IaC, GitOps, secrets, observabilité, CI).
2. Je sais raisonner quand ça casse (SLO, postmortems, debug en profondeur).

Livrables finaux :

| Repo | Rôle | Priorité |
|---|---|---|
| `platform-eks-gitops` | Plateforme Kubernetes GitOps sur EKS (comble le gap AWS) | P1 |
| `portfolio-site` | Site vitrine + debug stories | P2 |
| `llm-platform-sre` | SRE d'une appli LLM/RAG (différenciateur) | P3 |
| `<username>/<username>` | README de profil GitHub | P4 |

Règle d'or : **3 projets finis et documentés valent mieux que 8 repos commencés.**

---

## Phase 0 — Setup (1 soirée)

- [x] Compte GitHub : photo, bio, lien LinkedIn
- [x] Compte AWS perso, via la nouvelle inscription AWS à « projets » : pas d'utilisateur root ni IAM, connexion par fournisseur d'identité avec 2FA, région imposée `eu-north-1`
- [x] MFA (TOTP) ajouté dans AWS Settings
- [x] **AWS Budgets : alertes à 5 $ et 10 $ par mail (crédits exclus), plus une limite de dépenses à 20 $ qui bloque le projet**
- [x] AWS CLI : `aws login --profile perso` (identifiants temporaires 12 h, zéro clé stockée)
- [x] MCP AWS pour l'assistant IA : lecture seule, toute écriture demande confirmation
- [x] Outils locaux : `k3d` (ou `kind`), `kubectl`, `helm`, `terraform`, `argocd` CLI, `aws` CLI, `pre-commit`, `tflint`, `checkov`, `kubeconform`
- [x] Créer le repo `platform-eks-gitops`, y déposer `PLAN.md` et `CLAUDE.md`

---

## Phase 1 — `platform-eks-gitops` (2 à 3 semaines)

Principe : **tout se développe en local sur k3d**, EKS ne sert qu'à valider et faire la démo, puis `make down`.

### 1.1 Squelette du repo
```
platform-eks-gitops/
├── terraform/
│   ├── bootstrap/        # bucket S3 du state (lockfile S3 natif)
│   ├── modules/          # vpc, eks, iam
│   └── envs/demo/
├── gitops/
│   ├── bootstrap/        # app-of-apps ArgoCD
│   ├── platform/         # composants plateforme (1 dossier = 1 Application)
│   └── apps/             # appli de démo
├── apps/demo-api/        # code de l'appli de démo + Dockerfile
├── docs/
│   ├── architecture.md   # schéma Mermaid
│   ├── adr/              # Architecture Decision Records
│   └── runbooks/
├── .github/workflows/
├── Makefile              # make local-up / local-down / up / down
├── PLAN.md
└── CLAUDE.md
```

### 1.2 Plateforme en local (k3d)
- [ ] `make local-up` : cluster k3d + install ArgoCD + app-of-apps
- [ ] Ingress via **Gateway API** (Envoy Gateway ou Traefik) — ingress-nginx est en fin de vie, montrer qu'on suit l'écosystème
- [ ] cert-manager
- [ ] External Secrets Operator (backend local : Vault en mode dev ; sur AWS : Secrets Manager)
- [ ] kube-prometheus-stack (Prometheus, Alertmanager, Grafana)
- [ ] Sloth (ou Pyrra) pour générer les règles SLO
- [ ] Sync waves ArgoCD pour l'ordre (CRDs → opérateurs → apps)

### 1.3 Appli de démo + SLO
- [ ] Petite API (Go ou Python) exposant `/metrics` (latence, erreurs), avec un endpoint pour injecter des erreurs/latence
- [ ] Chart Helm ou kustomize, déployé par ArgoCD
- [ ] SLO disponibilité 99,5 % et latence p95 < 300 ms, alertes **multi-window burn-rate**
- [ ] Dashboard Grafana versionné (JSON dans le repo)
- [ ] Un runbook par alerte dans `docs/runbooks/`

### 1.4 AWS EKS avec Terraform
- [ ] `terraform/bootstrap` : bucket S3 versionné + chiffré pour le state
- [ ] VPC **sans NAT Gateway** (nœuds en subnets publics avec SG stricts, ou VPC endpoints) — justifier dans un ADR
- [ ] EKS + managed node group en **Spot**, taille minimale
- [ ] **EKS Pod Identity** (ou IRSA) pour ESO → Secrets Manager
- [ ] `make up` : terraform apply + bootstrap ArgoCD pointant sur le même repo
- [ ] `make down` : suppression des ressources Kubernetes créant des LB, puis terraform destroy
- [ ] Vérifier après `make down` qu'il ne reste rien (LB, EIP, volumes EBS)

### 1.5 CI GitHub Actions
- [ ] Terraform : `fmt -check`, `validate`, `tflint`, `checkov`
- [ ] Kubernetes : `kubeconform`, `helm lint`, `kustomize build`
- [ ] Build + scan (Trivy) + push de l'image de démo sur GHCR
- [ ] Authentification AWS par **OIDC GitHub → rôle IAM**, zéro clé statique
- [ ] `pre-commit` en local avec les mêmes checks

### 1.6 Documentation (autant de valeur que le code)
- [ ] README : problème, architecture (Mermaid), quickstart local en 3 commandes, choix techniques, coût réel d'une démo
- [ ] 3 à 5 ADR (ex. : pas de NAT, Gateway API vs Ingress, Pod Identity vs IRSA, app-of-apps)
- [ ] Captures : ArgoCD, dashboard SLO, alerte déclenchée
- [ ] Section « Ce que je ferais en prod » (multi-AZ, Karpenter, backup Velero, policies Kyverno…)

**Definition of done** : un inconnu clone le repo et fait tourner la plateforme en local en moins de 15 min.

---

## Phase 2 — `portfolio-site` (1 semaine)

- [ ] Astro (ou Hugo), hébergé sur GitHub Pages
- [ ] Pages : Accueil (positionnement en 2 phrases), Projets, Expérience, Debug stories, Contact
- [ ] CI : build, lint, Lighthouse CI (score ≥ 90), check des liens morts
- [ ] Optionnel : nom de domaine (~10-15 €/an)

**Page Expérience** : chaque point formulé comme un problème résolu, pas un outil utilisé. Échelle (400+ serveurs Linux critiques on-prem), astreinte, Ansible, RKE2/Rancher, Vault/ESO, ELK, mentorat d'alternants. **Rien de confidentiel.**

---

## Phase 3 — Debug stories (en continu, 1 par semaine)

Format postmortem court, sans blâme, **entièrement anonymisé** (aucun nom d'entreprise, host, IP, index, URL interne).

Structure : Symptôme → Impact → Fausses pistes → Cause racine → Fix → Ce que j'en retiens.

Idées de sujets :
- [ ] Kustomize : noms hashés de ConfigMap non propagés à une CronJob (transformer `nameReference` et contexte de namespace)
- [ ] nginx/OpenResty : auth cassée par la portée des variables entre subrequests
- [ ] Apache : compression gzip cassée par le préfixe `REDIRECT_` après rewrite interne
- [ ] « Ce n'était pas TLS » : échec de handshake causé par la segmentation réseau L3
- [ ] Elasticsearch : conflit de mapping entre index d'un même pattern

Bonus : reproduire le bug dans un mini-repo ou dans k3d quand c'est possible.

---

## Phase 4 — `llm-platform-sre` (2 à 3 semaines)

Version **générique**, aucun code ni donnée de l'employeur.

- [ ] API FastAPI de RAG sur un corpus public (ex. documentation open source)
- [ ] Qdrant (vector store), un provider LLM avec fallback, Langfuse (traces LLM)
- [ ] Déploiement sur la plateforme de la phase 1 (réutilisation = cohérence)
- [ ] SLO spécifiques IA : latence p95 bout en bout, taux d'erreur provider, coût en tokens par requête
- [ ] Dashboards : latence par étape (retrieval / génération), coût, erreurs
- [ ] Runbooks : provider en panne, latence qui explose, dérive de coût
- [ ] Test de charge (k6) avec résultats commentés

---

## Phase 5 — Finalisation

- [ ] README de profil GitHub : 2 phrases de positionnement, 3 projets, lien site
- [x] Épingler les 3 repos (fait dès le départ, pour que le profil soit présentable)
- [ ] Mettre à jour les 3 versions de CV avec les liens
- [ ] Post LinkedIn de lancement (1 projet = 1 post, avec schéma)

---

## Règles de travail

- Commits petits et réguliers, messages en Conventional Commits (`feat:`, `fix:`, `docs:`…)
- Une phase = une branche + une PR (même seul : ça montre le process)
- Jamais de secret dans le repo (`gitleaks` en pre-commit)
- Cloud : `make down` à la fin de chaque session, sans exception
