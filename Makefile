# NeMo Unified Studio
# Run 'make help' for available commands

SHELL := /bin/bash

# Load .env if exists (silently fail if not)
-include .env
export

# Defaults
AWS_PROFILE ?= default
AWS_REGION ?= us-east-1

# Environments for 'make setup-all-envs' (space-delimited)
ENVS := eksnemohyperpodsmus1 eksnemohyperpodsmus2 nvidianemo hypersmusnemo

.PHONY: help env env-shell env-run sync artifacts blueprint provisioning-policy nested-stack-policy domain-role ngc-secret hf-secret container-build az-rotation-build setup-all setup-all-envs cfn-follow

help:
	@echo "NeMo Unified Studio"
	@echo ""
	@echo "Environment:"
	@echo "  make env ENV=name       Switch to .env.{name}"
	@echo "  make env-show           Show current config"
	@echo "  make env-shell [ENV=name] Start a shell with .env exported"
	@echo "  make env-run CMD=... [ENV=name] Run a command with .env exported"
	@echo ""
	@echo "CloudFormation:"
	@echo "  make cfn-follow STACK_ARN=... [ENV=name] Follow stack + nested events (stdout + logs/ file)"
	@echo ""
	@echo "Templates:"
	@echo "  make artifacts          Generate Lambda/container artifacts"
	@echo "  make sync               Sync HyperPod templates to S3"
	@echo ""
	@echo "Blueprint Setup:"
	@echo "  make blueprint          Create/update DataZone blueprint"
	@echo "  make provisioning-policy  Setup provisioning role policy"
	@echo "  make nested-stack-policy  Setup nested stack policy"
	@echo "  make domain-role        Setup domain connection role"
	@echo ""
	@echo "Container Pipeline:"
	@echo "  make ngc-secret KEY=xxx Update NGC API key secret"
	@echo "  make hf-secret TOKEN=xxx Update Hugging Face access token secret"
	@echo "  make container-build    Build NeMo container"
	@echo "  make az-rotation-build  Build AZ rotation controller image"
	@echo ""
	@echo "Full Setup:"
	@echo "  make setup-all          Run all setup steps"

# Environment
env:
ifndef ENV
	$(error Usage: make env ENV=name)
endif
	@test -f .env.$(ENV) || (echo "Error: .env.$(ENV) not found" && exit 1)
	@ln -sf .env.$(ENV) .env
	@echo "Switched to $(ENV)"

env-show:
	@echo "Config: $$(readlink .env 2>/dev/null || echo '.env')"
	@echo "AWS_PROFILE=$(AWS_PROFILE)"
	@echo "AWS_REGION=$(AWS_REGION)"
	@echo "DOMAIN_ID=$(DOMAIN_ID)"

env-shell:
	@if [ -n "$(ENV)" ]; then $(MAKE) env ENV=$(ENV); fi
	@bash -lc 'set -a; source .env; set +a; exec "$${SHELL:-/bin/bash}"'

env-run:
ifndef CMD
	$(error Usage: make env-run CMD="aws s3 ls")
endif
	@if [ -n "$(ENV)" ]; then $(MAKE) env ENV=$(ENV); fi
	@bash -lc 'set -a; source .env; set +a; $(CMD)'

# CloudFormation
cfn-follow:
ifndef STACK_ARN
	$(error Usage: make cfn-follow STACK_ARN=arn:aws:cloudformation:... [ENV=name])
endif
	@if [ -n "$(ENV)" ]; then $(MAKE) env ENV=$(ENV); fi
	@bash -lc 'set -a; source .env; set +a; \
	  scripts/follow-cfn-stack-events.sh --no-tmux "$(STACK_ARN)"'

# Templates
artifacts:
	@./sagemaker-hyperpod-cluster-setup/eks/cloudformation/resources/artifacts/generate-all-artifacts.sh

sync:
	@./sagemaker-hyperpod-cluster-setup/scripts/sync-to-s3.sh

# Blueprint
blueprint:
	@python3 ./blueprints/scripts/setup-blueprint.py

provisioning-policy:
	@./blueprints/scripts/setup-provisioning-role-policy.sh

nested-stack-policy:
	@./blueprints/scripts/setup-nested-stack-policy.sh

domain-role:
	@python3 ./blueprints/scripts/setup_domain_connection_role.py

# Container Pipeline
ngc-secret:
ifdef KEY
	@NGC_KEY="$(KEY)" ./nemo-container-pipeline/scripts/update-ngc-secret.sh
else
	@./nemo-container-pipeline/scripts/update-ngc-secret.sh
endif

hf-secret:
ifdef TOKEN
	@HF_ACCESS_TOKEN="$(TOKEN)" ./nemo-container-pipeline/scripts/update-hf-secret.sh
else
	@./nemo-container-pipeline/scripts/update-hf-secret.sh
endif

secrets: hf-secret ngc-secret
	@echo "✓ Setup complete"

setup-all-envs-secrets:
	@for e in $(ENVS); do \
		echo "=== Setting up $$e ==="; \
		$(MAKE) env ENV=$$e; \
		$(MAKE) secrets; \
		echo ""; \
	done
	@echo "=== All environments configured ==="

container-build:
	@./nemo-container-pipeline/scripts/deploy-and-build.sh

llmft-container-build:
	@./llmft-container-pipeline/scripts/deploy-and-build.sh

setup-all-containers: container-build llmft-container-build
	@echo "✓ Setup complete"

setup-all-container-envs:
	@for e in $(ENVS); do \
		echo "=== Setting up $$e ==="; \
		$(MAKE) env ENV=$$e; \
		$(MAKE) setup-all-containers; \
		echo ""; \
	done
	@echo "=== All environments configured ==="

# Full setup (current env)
setup-all: provisioning-policy nested-stack-policy sync blueprint
	@echo "✓ Setup complete"


setup-all-nosync: provisioning-policy nested-stack-policy blueprint
	@echo "✓ Setup complete"

# Setup all environments listed in ENVS
setup-all-envs:
	@for e in $(ENVS); do \
		echo "=== Setting up $$e ==="; \
		$(MAKE) env ENV=$$e; \
		$(MAKE) setup-all; \
		echo ""; \
	done
	@echo "=== All environments configured ==="

# Setup all environments listed in ENVS
setup-all-envs-nosync:
	@for e in $(ENVS); do \
		echo "=== Setting up $$e ==="; \
		$(MAKE) env ENV=$$e; \
		$(MAKE) setup-all-nosync; \
		echo ""; \
	done
	@echo "=== All environments configured ==="
