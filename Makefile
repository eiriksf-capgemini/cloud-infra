# Thin wrapper around OpenTofu so every stack is driven the same way.
#
#   make init  STACK=live/azure/poc/10-network
#   make plan  STACK=live/azure/poc/20-cluster     # review, then:
#   make apply STACK=live/azure/poc/20-cluster     # applies the saved plan, no prompt
#   make validate-all          # init -backend=false + validate every module and stack
#
# STACK is a path relative to the repo root. Stacks under live/<cloud>/<env>/
# share a backend.hcl one directory up, which `init` picks up automatically.

STACK ?= live/azure/poc/10-network
TOFU  ?= tofu

# Cache provider binaries across stacks so repeated `init` runs are fast.
export TF_PLUGIN_CACHE_DIR ?= $(HOME)/.terraform.d/plugin-cache

BACKEND_HCL := $(wildcard $(STACK)/../backend.hcl)
BACKEND_ARG := $(if $(BACKEND_HCL),-backend-config=../backend.hcl,)

.PHONY: help init plan apply destroy output fmt fmt-check validate validate-all clean aks-stop aks-start aks-wait aks-status allowlist-refresh

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

init: ## tofu init for STACK (uses ../backend.hcl if present)
	@mkdir -p $(TF_PLUGIN_CACHE_DIR)
	cd $(STACK) && $(TOFU) init -input=false $(BACKEND_ARG)

plan: ## tofu plan for STACK; saves STACK/tfplan for `make apply`
	cd $(STACK) && $(TOFU) plan -input=false -out=tfplan

apply: ## apply the plan saved by `make plan` (non-interactive; review the plan first)
	@test -f $(STACK)/tfplan || { echo "no $(STACK)/tfplan: run 'make plan STACK=$(STACK)' first"; exit 1; }
	cd $(STACK) && $(TOFU) apply -input=false tfplan && rm -f tfplan

destroy: ## tofu destroy for STACK
	cd $(STACK) && $(TOFU) destroy -input=false

output: ## tofu output for STACK
	cd $(STACK) && $(TOFU) output

fmt: ## Format all HCL in place
	$(TOFU) fmt -recursive

fmt-check: ## Fail if any HCL is not formatted
	$(TOFU) fmt -check -recursive -diff

validate: ## Validate STACK without a backend or credentials
	@mkdir -p $(TF_PLUGIN_CACHE_DIR)
	cd $(STACK) && $(TOFU) init -backend=false -input=false >/dev/null && $(TOFU) validate

validate-all: ## Validate every module and stack (no credentials needed)
	@mkdir -p $(TF_PLUGIN_CACHE_DIR)
	@set -e; for d in $$(find modules live -name '*.tf' -not -path '*/.terraform/*' -exec dirname {} \; | sort -u); do \
		printf '\n== %s\n' "$$d"; \
		( cd "$$d" && $(TOFU) init -backend=false -input=false >/dev/null && $(TOFU) validate ); \
	done

clean: ## Remove local .terraform dirs (keeps lock files and state)
	find . -type d -name .terraform -prune -exec rm -rf {} +

# --- Cost controls: manual stop/start of the POC cluster (see ADR 0004) ---
AKS_RG   ?= rg-cloudinfra-poc
AKS_NAME ?= aks-cloudinfra-poc

aks-stop: ## Stop the AKS cluster now (no node compute billed while stopped)
	az aks stop --resource-group $(AKS_RG) --name $(AKS_NAME)

aks-start: ## Start the AKS cluster and poll until the console is usable (prints each stage; ~5-10 min)
	AKS_RG=$(AKS_RG) AKS_NAME=$(AKS_NAME) scripts/aks-start-wait.sh

aks-wait: ## Poll a running cluster until the console is usable (no start)
	AKS_RG=$(AKS_RG) AKS_NAME=$(AKS_NAME) scripts/aks-start-wait.sh --no-start

aks-status: ## Show the cluster power state
	az aks show --resource-group $(AKS_RG) --name $(AKS_NAME) --query '{name:name, power:powerState.code, nodes:agentPoolProfiles[].{pool:name,size:vmSize,count:count}}' -o json

# --- Access control: regenerate the country allowlist used by the ingress NSG (ADR 0009) ---
COUNTRY ?= NO

ALLOWLIST_FILE = live/azure/poc/allowlist/$(shell echo $(COUNTRY) | tr A-Z a-z)-ipv4.txt

allowlist-refresh: ## Regenerate live/azure/poc/allowlist/<country>-ipv4.txt from RIPEstat (then commit + apply 10-network)
	@set -e; tmp=$$(mktemp); \
	python3 scripts/country-prefixes.py $(COUNTRY) > $$tmp; \
	mv $$tmp $(ALLOWLIST_FILE); \
	echo "$$(grep -c -v '^#' $(ALLOWLIST_FILE)) prefixes -> $(ALLOWLIST_FILE)"
