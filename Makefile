SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

# Personal settings, such as AWS_PROFILE, go in local.mk, which is not committed.
-include local.mk

CLUSTER_NAME   := platform-local
ARGOCD_CHART   := 10.9.2
ARGOCD_NS      := argocd
# Branch Argo CD follows. Override while developing: make local-up REVISION=my-branch
REVISION       ?= main

# Which cluster every target talks to. Each environment has a kubeconfig file of
# its own and is the only thing in it; ~/.kube/config, and whatever other
# clusters it holds, is never read and never written. Without this, a target
# would act on the current context, whichever cluster that happens to be.
LOCAL_KUBECONFIG := $(HOME)/.kube/platform-eks-gitops-local
AWS_KUBECONFIG   := $(HOME)/.kube/platform-eks-gitops-aws
ENV              ?= local
export KUBECONFIG = $(if $(filter aws,$(ENV)),$(AWS_KUBECONFIG),$(LOCAL_KUBECONFIG))

# The AWS targets always talk to the AWS cluster, whatever ENV says.
up plan down aws-argocd aws-bootstrap aws-wait aws-info aws-verify aws-gateway-url: ENV = aws

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

.PHONY: check-tools
check-tools: ## Check the tools the local platform needs (GROUP=aws, dev or all to require more)
	@scripts/check-tools.sh $(or $(GROUP),local)

.PHONY: lint
lint: ## Run all linters and security checks
	pre-commit run -a

## ---- Local (k3d, free) ----

.PHONY: local-up
local-up: local-cluster demo-image local-argocd local-bootstrap local-wait local-info ## Create the k3d cluster and bootstrap the whole platform

.PHONY: local-cluster
local-cluster: ## Create the k3d cluster (no-op if it already exists)
	@if k3d cluster list $(CLUSTER_NAME) >/dev/null 2>&1; then \
		echo "cluster $(CLUSTER_NAME) already exists"; \
	else \
		k3d cluster create --config local/k3d-cluster.yaml; \
	fi
	@$(MAKE) --no-print-directory local-kubeconfig

.PHONY: local-kubeconfig
local-kubeconfig: ## Write the local cluster's credentials to its own kubeconfig file
	@mkdir -p $(dir $(LOCAL_KUBECONFIG))
	@k3d kubeconfig write $(CLUSTER_NAME) --output $(LOCAL_KUBECONFIG) >/dev/null
	@chmod 600 $(LOCAL_KUBECONFIG)
	@echo "kubeconfig: $(LOCAL_KUBECONFIG)"

.PHONY: context
context: ## Show which cluster the targets talk to (ENV=local or ENV=aws)
	@echo "environment: $(ENV)"
	@echo "kubeconfig:  $$KUBECONFIG"
	@contexts=$$(kubectl config get-contexts -o name 2>/dev/null); \
	if [ -n "$$contexts" ]; then echo "$$contexts" | sed 's/^/context:     /'; \
	else echo "context:     none, this environment is not running"; fi

.PHONY: local-argocd
local-argocd: ## Install Argo CD with Helm
	helm upgrade --install argocd argo-cd \
		--repo https://argoproj.github.io/argo-helm \
		--version $(ARGOCD_CHART) \
		--namespace $(ARGOCD_NS) --create-namespace \
		--values local/argocd-values.yaml \
		--wait --timeout 10m

.PHONY: local-bootstrap
local-bootstrap: ## Apply the root Application (app-of-apps)
	@sed 's|targetRevision: main|targetRevision: $(REVISION)|' \
		gitops/bootstrap/local/root-app.yaml | kubectl apply -f -
	@# Applications in git always track `main`. When testing a branch, repoint them.
	@if [ "$(REVISION)" != "main" ]; then \
		sleep 10; scripts/dev-follow-revision.sh $(REVISION) $(ARGOCD_NS); \
	fi

.PHONY: local-wait
local-wait: ## Wait for every Argo CD Application to become healthy
	@echo "waiting for applications to sync (this pulls charts, give it a few minutes)..."
	@scripts/wait-for-apps.sh $(ARGOCD_NS) 600

.PHONY: local-info
local-info: ## Print how to reach Argo CD and the gateway
	@echo ""
	@echo "Argo CD:  make argocd-ui   then http://localhost:8081 (user: admin)"
	@echo "Password: make argocd-password"
	@echo "Check:    make local-verify"
	@echo "Grafana:  https://grafana.platform.local:8443 (user: admin, make grafana-password)"
	@echo "Demo API: https://demo.platform.local:8443"
	@echo "          both names resolve to 127.0.0.1 once added to /etc/hosts, see the README"

.PHONY: demo-image
demo-image: ## Build the demo API image and import it into the k3d cluster
	docker build -t demo-api:dev apps/demo-api
	k3d image import demo-api:dev --cluster $(CLUSTER_NAME)
	kubectl rollout restart deployment/demo-api -n demo 2>/dev/null || true

.PHONY: demo-load
demo-load: ## Send traffic to the demo API (make demo-load SECONDS=120 RPS=10)
	@scripts/demo-traffic.sh load $(or $(SECONDS),60) $(or $(RPS),5)

.PHONY: demo-break
demo-break: ## Make the demo API fail (make demo-break RATE=0.3 LATENCY=0)
	@scripts/demo-traffic.sh break $(or $(RATE),0.3) $(or $(LATENCY),0)

.PHONY: demo-fix
demo-fix: ## Stop the injected failures
	@scripts/demo-traffic.sh fix

.PHONY: demo-debug
demo-debug: ## Attach a shell to a running demo API pod (the image itself has none)
	@pod=$$(kubectl get pod -n demo -l app.kubernetes.io/name=demo-api \
		--field-selector=status.phase=Running -o name | head -1); \
	echo "attaching to $$pod, the API's files are under /proc/1/root/app"; \
	kubectl debug -n demo -it $$pod --image=busybox:1.37 --target=demo-api

.PHONY: local-verify
local-verify: ## Check the platform end to end (applications, gateway, secrets)
	@scripts/verify-local.sh $(ARGOCD_NS)

.PHONY: grafana-password
grafana-password: ## Print the Grafana admin password (generated in the secret store)
	@kubectl get secret -n monitoring grafana-admin \
		-o jsonpath='{.data.admin-password}' | base64 -d; echo

.PHONY: local-status
local-status: ## Show Argo CD applications and platform pods
	@kubectl get applications.argoproj.io -n $(ARGOCD_NS)
	@kubectl get pods -A --field-selector=status.phase!=Running 2>/dev/null | head -20

.PHONY: argocd-ui
argocd-ui: ## Port-forward the Argo CD UI to http://localhost:8081
	kubectl port-forward -n $(ARGOCD_NS) svc/argocd-server 8081:80

.PHONY: prometheus-ui
prometheus-ui: ## Port-forward Prometheus to http://localhost:9090 (targets, rules, alerts)
	kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

.PHONY: alertmanager-ui
alertmanager-ui: ## Port-forward Alertmanager to http://localhost:9093
	kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093

.PHONY: argocd-password
argocd-password: ## Print the initial Argo CD admin password
	@kubectl get secret -n $(ARGOCD_NS) argocd-initial-admin-secret \
		-o jsonpath='{.data.password}' | base64 -d; echo

.PHONY: local-restart
local-restart: ## Stop and start the cluster (refreshes node DNS, reloads generated secrets)
	k3d cluster stop $(CLUSTER_NAME)
	k3d cluster start $(CLUSTER_NAME)
	@$(MAKE) --no-print-directory local-kubeconfig
	@# Vault runs in dev mode, so a restart wipes it and regenerates the Grafana
	@# password. Grafana only reads it at startup, so it has to be restarted after
	@# External Secrets has published the new value.
	@echo "waiting for the regenerated secrets, then reloading Grafana..."
	@sleep 60
	@kubectl rollout restart deploy/kube-prometheus-stack-grafana -n monitoring 2>/dev/null || true

.PHONY: grafana-reload
grafana-reload: ## Restart Grafana so it picks up a regenerated admin password
	kubectl rollout restart deploy/kube-prometheus-stack-grafana -n monitoring
	kubectl rollout status deploy/kube-prometheus-stack-grafana -n monitoring --timeout=180s

.PHONY: local-down
local-down: ## Delete the k3d cluster
	k3d cluster delete $(CLUSTER_NAME)
	@rm -f $(LOCAL_KUBECONFIG)

## ---- AWS (EKS, costs money: always finish with `make down`) ----

# No default profile, on purpose: on a machine that knows several AWS accounts,
# the wrong default is one keystroke away. Export it, or set it in local.mk.
AWS_PROFILE ?=
AWS_REGION  ?= eu-north-1
TF_DEMO     := terraform/envs/demo
# The Kubernetes API is reachable from this machine only. Override with
# MY_IP=x.x.x.x if the detection fails or you are behind a changing address.
MY_IP       ?= $(shell curl -fsS --max-time 5 https://checkip.amazonaws.com || echo detection-failed)
TF_API_CIDR := -var=api_public_access_cidrs=["\"$(MY_IP)/32\""]

# What every AWS target needs before it touches anything: a profile chosen on
# purpose, the tools, and the two files the README asks to create once.
.PHONY: aws-profile
aws-profile:
	@[ -n "$(AWS_PROFILE)" ] || { \
		echo "AWS_PROFILE is not set. Export it, or keep it in local.mk:"; \
		echo "  echo 'AWS_PROFILE := <your profile>' >> local.mk"; exit 1; }

.PHONY: aws-preflight
aws-preflight: aws-profile
	@QUIET=1 scripts/check-tools.sh aws
	@for f in backend.hcl terraform.tfvars; do \
		[ -f $(TF_DEMO)/$$f ] || { \
			echo "$(TF_DEMO)/$$f is missing: copy $$f.example and fill it in, see the README"; exit 1; }; \
	done

# An `aws login` session ends twelve hours after the login. The long operations
# refuse to start on one that might not last, rather than stop halfway with a
# cluster still billing (docs/runbooks).
.PHONY: aws-login
aws-login: aws-profile ## Open an AWS session with `aws login`, and note when it started
	@AWS_PROFILE=$(AWS_PROFILE) scripts/aws-session.sh login

.PHONY: aws-session
aws-session: aws-profile
	@AWS_PROFILE=$(AWS_PROFILE) scripts/aws-session.sh check 10

.PHONY: up
up: aws-preflight aws-session ## Create the EKS demo environment (about $0.18/hour, always finish with make down)
	@# No reference to the make variable on this line: GNU make runs any line that
	@# names it even under `make -n`, which would start a real deployment.
	@AWS_PROFILE=$(AWS_PROFILE) AWS_REGION=$(AWS_REGION) TF_DIR=$(TF_DEMO) MY_IP=$(MY_IP) scripts/aws-up.sh

.PHONY: aws-argocd
aws-argocd: ## Install Argo CD on the EKS cluster
	helm upgrade --install argocd argo-cd \
		--repo https://argoproj.github.io/argo-helm \
		--version $(ARGOCD_CHART) \
		--namespace $(ARGOCD_NS) --create-namespace \
		--values aws/argocd-values.yaml \
		--wait --timeout 10m

.PHONY: aws-bootstrap
aws-bootstrap: ## Apply the AWS root Application (app-of-apps)
	@sed 's|targetRevision: main|targetRevision: $(REVISION)|' \
		gitops/bootstrap/aws/root-app.yaml | kubectl apply -f -
	@if [ "$(REVISION)" != "main" ]; then \
		sleep 10; ROOT_APP=root-aws scripts/dev-follow-revision.sh $(REVISION) $(ARGOCD_NS); \
	fi

.PHONY: aws-wait
aws-wait: ## Wait for the AWS applications to converge
	@echo "waiting for applications to sync..."
	@scripts/wait-for-apps.sh $(ARGOCD_NS) 900

.PHONY: aws-info
aws-info: ## Print how to reach the platform on AWS
	@echo
	@echo "Check:    make aws-verify"
	@echo "Argo CD:  make argocd-ui ENV=aws   then http://localhost:8081 (user: admin)"
	@echo "Password: make argocd-password ENV=aws"
	@echo "Gateway:  make aws-gateway-url"
	@echo
	@echo "This is billing by the hour: make down when you are finished."

.PHONY: aws-verify
aws-verify: ## Check the EKS platform end to end
	@scripts/verify-aws.sh $(ARGOCD_NS)

.PHONY: aws-gateway-url
aws-gateway-url: ## Print the load balancer address of the gateway
	@kubectl get svc -n envoy-gateway-system \
		-l gateway.envoyproxy.io/owning-gateway-name=platform \
		-o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}{"\n"}'

.PHONY: plan
plan: aws-preflight ## Show what `make up` would create, without creating it
	AWS_PROFILE=$(AWS_PROFILE) terraform -chdir=$(TF_DEMO) init -backend-config=backend.hcl -input=false
	AWS_PROFILE=$(AWS_PROFILE) terraform -chdir=$(TF_DEMO) plan -input=false $(TF_API_CIDR)

.PHONY: down
down: aws-preflight aws-session ## Destroy the EKS demo environment and check nothing is left billing
	@AWS_PROFILE=$(AWS_PROFILE) AWS_REGION=$(AWS_REGION) TF_DIR=$(TF_DEMO) scripts/aws-down.sh

.PHONY: cost
cost: aws-profile ## Show this month's AWS spend, credits excluded (one Cost Explorer call, billed $0.01)
	@# Credits are subtracted by default, which reports roughly zero while free
	@# credits last and hides what the environment actually consumes. Excluding
	@# them answers the question worth asking: what would this cost for real?
	@AWS_PROFILE=$(AWS_PROFILE) aws ce get-cost-and-usage \
		--time-period Start=$$(date -u +%Y-%m-01),End=$$(date -u -d tomorrow +%Y-%m-%d) \
		--granularity MONTHLY --metrics UnblendedCost \
		--filter '{"Not":{"Dimensions":{"Key":"RECORD_TYPE","Values":["Credit","Refund"]}}}' \
		--query 'ResultsByTime[0].Total.UnblendedCost.[Amount,Unit]' --output text

.PHONY: cost-by-service
cost-by-service: aws-profile ## Break this month's spend down by service (one Cost Explorer call, billed $0.01)
	@AWS_PROFILE=$(AWS_PROFILE) aws ce get-cost-and-usage \
		--time-period Start=$$(date -u +%Y-%m-01),End=$$(date -u -d tomorrow +%Y-%m-%d) \
		--granularity MONTHLY --metrics UnblendedCost \
		--filter '{"Not":{"Dimensions":{"Key":"RECORD_TYPE","Values":["Credit","Refund"]}}}' \
		--group-by Type=DIMENSION,Key=SERVICE \
		--query 'ResultsByTime[0].Groups[?Metrics.UnblendedCost.Amount!=`0`].[Keys[0],Metrics.UnblendedCost.Amount]' \
		--output text | sort -k2 -rn
