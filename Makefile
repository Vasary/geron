SHELL := bash

TALOS_DIR := talos
HELM_DIR := helm

.DEFAULT_GOAL := help

.PHONY: help talos helm helm-% validate deploy deploy-secrets

help:
	@$(MAKE) -C "$(TALOS_DIR)" help
	@printf '%s\n' \
		'' \
		'Structure:' \
		'  talos/   Talos configs, patches, scripts, generated manifests, secrets' \
		'  helm/    Argo CD bootstrap, projects and cluster applications' \
		'' \
		'Cluster app targets:' \
		'  make helm                 Show Argo CD / Helm app targets' \
		'  make validate             Validate Argo CD platform manifests' \
		'  make deploy               Install Argo CD and bootstrap from git origin' \
		'  make deploy-secrets       Decrypt and apply SOPS Kubernetes secrets' \
		'  make helm-validate        Validate Argo CD platform manifests' \
		'  make helm-deploy          Install Argo CD and bootstrap from git origin' \
		'  make helm-deploy-secrets  Decrypt and apply SOPS Kubernetes secrets'

talos:
	@$(MAKE) -C "$(TALOS_DIR)" help

helm:
	@$(MAKE) -C "$(HELM_DIR)" help

helm-%:
	@$(MAKE) -C "$(HELM_DIR)" $*

validate deploy deploy-secrets:
	@$(MAKE) -C "$(HELM_DIR)" $@

%:
	@$(MAKE) -C "$(TALOS_DIR)" $@
