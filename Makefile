SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

REQUIRED_TOOLS := docker k3d kubectl helm terraform aws pre-commit

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.PHONY: check-tools
check-tools: ## Verify required CLI tools are installed
	@missing=0; for t in $(REQUIRED_TOOLS); do \
		command -v $$t >/dev/null || { echo "missing: $$t"; missing=1; }; \
	done; [ $$missing -eq 0 ] && echo "all tools found"

.PHONY: lint
lint: ## Run all linters and security checks
	pre-commit run -a

## ---- Local (k3d, free) ----

.PHONY: local-up
local-up: ## Create the k3d cluster and bootstrap ArgoCD
	@echo "not implemented yet (step 1.2)"; exit 1

.PHONY: local-down
local-down: ## Delete the k3d cluster
	@echo "not implemented yet (step 1.2)"; exit 1

## ---- AWS (EKS, costs money: always finish with `make down`) ----

.PHONY: up
up: ## Create the EKS demo environment and bootstrap ArgoCD
	@echo "not implemented yet (step 1.4)"; exit 1

.PHONY: down
down: ## Destroy the EKS demo environment
	@echo "not implemented yet (step 1.4)"; exit 1
