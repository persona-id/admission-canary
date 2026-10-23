# Local development deploys kubernetes/jsonnet/local/main.jsonnet to a stable
# per-developer namespace (frontier-<app>-dev-<DEV_USER>), outside ArgoCD. kro
# creates the namespace from the Frontier resource make bootstrap applies.
# Set DEV_USER (e.g. DEV_USER=jane-foo make dev) only to run a second,
# isolated dev deploy in parallel with your default one.
DEV_USER ?= $(shell whoami | tr '[:upper:]' '[:lower:]')

KUBE_CONTEXT := frontier-us-central1-k8s-api.withpersona.ts.net
KUBECTL := kubectl --context $(KUBE_CONTEXT)

# The cluster identity of whoever runs make dev, e.g. jane@withpersona.com. It
# owns the dev namespace, so kro's RoleBindings let them deploy to it. Separate
# from DEV_USER, which only names the namespace.
KUBE_USER = $(shell $(KUBECTL) auth whoami -o jsonpath='{.status.userInfo.username}' 2>/dev/null)

JSONNET_DIR := kubernetes/jsonnet
JSONNET := cd $(JSONNET_DIR) && jsonnet -J vendor
# These come from the jsonnet config, so skaffold builds and deploys what it renders.
LOCAL_CONFIG := (import 'local/config.libsonnet')('$(DEV_USER)')
IMAGE_REPO = $(shell $(JSONNET) -S -e "$(LOCAL_CONFIG).image.repository")
NAMESPACE = $(shell $(JSONNET) -S -e "$(LOCAL_CONFIG).namespace")
FRONTIER_NAME = $(shell $(JSONNET) -S -e "$(LOCAL_CONFIG).appName")

# skaffold resolves paths against the working directory, so its rendered
# config lives in the repo next to the manifests it deploys.
SKAFFOLD_CONFIG := .skaffold/skaffold.yaml

.PHONY: dev dev-debug dev-remote dev-render render bootstrap setup dev-delete login help status setup-context

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

login: ## Login to GHCR (required before first deploy)
	@gh auth status >/dev/null 2>&1 || gh auth login
	@gh auth refresh -s write:packages,repo
	@echo "Logging into GHCR..."
	@gh auth token | docker login ghcr.io -u $$(gh api user -q .login) --password-stdin

setup-context: ## Configure kubectl to connect to the Frontier cluster via Tailscale
	@if [ -z "$$CI" ]; then \
		tailscale configure kubeconfig https://frontier-us-central1-k8s-api; \
	fi

render: ## Render the local jsonnet and skaffold config into .skaffold/
	@mkdir -p .skaffold
	$(JSONNET) -y --tla-str user=$(DEV_USER) \
		--tla-str revision="$$(sh $(CURDIR)/bin/source-provenance revision)" \
		--tla-str dirty="$$(sh $(CURDIR)/bin/source-provenance dirty)" \
		local/main.jsonnet >| $(CURDIR)/.skaffold/app.yaml
	IMAGE_REPO=$(IMAGE_REPO) NAMESPACE=$(NAMESPACE) KUBE_CONTEXT=$(KUBE_CONTEXT) \
		envsubst '$$IMAGE_REPO $$NAMESPACE $$KUBE_CONTEXT' < skaffold.yaml >| $(SKAFFOLD_CONFIG)

# Developers can't create namespaces. kro creates one, with the owner and
# collaborator RoleBindings, from a Frontier resource in frontier-system. Wait
# until the namespace exists and those RoleBindings let you read it.
bootstrap: setup-context render ## Create your dev namespace (applies the Frontier resource kro builds it from)
	@user='$(KUBE_USER)'; \
	case "$$user" in \
		*@withpersona.com) ;; \
		*) echo "Can't tell who you are on the cluster (kubectl auth whoami: '$$user'). Run make setup-context and check your Tailscale login."; exit 1 ;; \
	esac; \
	$(JSONNET) --tla-str user=$(DEV_USER) --tla-str owner="$${user%@withpersona.com}" local/frontier.jsonnet >| $(CURDIR)/.skaffold/frontier.json
	$(KUBECTL) apply -f .skaffold/frontier.json
	@echo "Waiting for kro to create $(NAMESPACE)..."
	@for i in $$(seq 60); do \
		$(KUBECTL) get serviceaccount default -n $(NAMESPACE) >/dev/null 2>&1 && exit 0; \
		sleep 2; \
	done; \
	echo "$(NAMESPACE) isn't ready. Check: $(KUBECTL) get frontier $(FRONTIER_NAME) -n frontier-system"; \
	exit 1

dev: bootstrap ## Deploy with file watching (local Docker builds)
	skaffold dev -f $(SKAFFOLD_CONFIG) --cleanup=false

dev-debug: bootstrap ## Deploy with file watching (debug mode)
	skaffold dev -f $(SKAFFOLD_CONFIG) --cleanup=false -v debug

dev-remote: bootstrap ## Deploy with file watching (remote Kaniko builds, no Docker needed)
	skaffold dev -f $(SKAFFOLD_CONFIG) --cleanup=false -p dev-remote-build

dev-render: render ## Render dev manifests without deploying
	skaffold render -f $(SKAFFOLD_CONFIG)

setup: ## Installs required utilities locally to support running local development tools in the repo
	brew install kubectl skaffold gh tailscale go-jsonnet
	@command -v docker >/dev/null 2>&1 || brew install orbstack

# kro deletes the namespace, and everything in it, with the Frontier resource.
dev-delete: setup-context ## Delete your dev deployment and its namespace
	$(KUBECTL) delete frontier $(FRONTIER_NAME) -n frontier-system --ignore-not-found

status: ## Show your dev deployment status
	@$(KUBECTL) get ksvc -n $(NAMESPACE) 2>/dev/null || echo "No Knative service found"
	@$(KUBECTL) get domainmapping -n $(NAMESPACE) 2>/dev/null || echo "No DomainMapping found"
	@$(KUBECTL) get pods -n $(NAMESPACE) 2>/dev/null || echo "No pods found"
