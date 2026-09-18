# Contexte projet

Ce repo fait partie de mon portfolio public DevOps / SRE / Platform Engineer, destiné à des recruteurs.
Le plan complet et l'avancement sont dans @PLAN.md : le lire avant toute tâche et cocher les cases terminées.

## Mon profil
- Ingénieur DevOps/SRE, expérience principale : infra Linux on-prem à grande échelle, astreinte
- Stack maîtrisée : Kubernetes (RKE2/Rancher), Terraform, Ansible, ArgoCD, Vault + External Secrets, Prometheus/Grafana, ELK
- Objectif de ce repo : démontrer aussi la maîtrise du cloud managé (AWS EKS)
- Me parler en français ; code, commentaires, commits et docs du repo en anglais

## Règles non négociables
- **Coût** : tout doit être destructible via `make down`. Pas de NAT Gateway, nœuds Spot, taille minimale. Toujours signaler une ressource qui coûte de l'argent avant de la créer.
- **Sécurité** : aucun secret, clé ou token dans le repo. Auth AWS en CI uniquement par OIDC.
- **Confidentialité** : ne jamais mentionner mon employeur, ses hosts, IP, URLs ou données. Tout exemple issu de mon expérience doit être anonymisé.
- **Local d'abord** : tout doit fonctionner sur k3d avant d'aller sur EKS.

## Façon de travailler
- Avancer phase par phase selon PLAN.md, une branche + une PR par étape
- Proposer un plan avant les changements importants, puis attendre ma validation
- Petits commits en Conventional Commits
- Pour chaque choix technique non trivial, proposer un ADR dans `docs/adr/`
- Préférer la simplicité et la lisibilité : ce repo doit être compris par un recruteur technique en 5 minutes
- Après chaque étape : mettre à jour le README si nécessaire et lancer les checks (`pre-commit run -a`)

## Commandes
- `make local-up` / `make local-down` : cluster k3d + ArgoCD
- `make up` / `make down` : environnement EKS de démo
- `pre-commit run -a` : lint et checks
