# Thin wrapper around OpenTofu so every stack is driven the same way.
#
#   make init  STACK=live/azure/poc/10-network
#   make plan  STACK=live/azure/poc/20-cluster
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

.PHONY: help init plan apply destroy output fmt fmt-check validate validate-all clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

init: ## tofu init for STACK (uses ../backend.hcl if present)
	@mkdir -p $(TF_PLUGIN_CACHE_DIR)
	cd $(STACK) && $(TOFU) init -input=false $(BACKEND_ARG)

plan: ## tofu plan for STACK
	cd $(STACK) && $(TOFU) plan -input=false

apply: ## tofu apply for STACK (interactive approval)
	cd $(STACK) && $(TOFU) apply -input=false

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
