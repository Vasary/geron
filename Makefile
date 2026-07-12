SHELL := bash

TALOS_DIR := talos
HELM_DIR := helm

.DEFAULT_GOAL := help

.PHONY: help talos helm helm-%

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
		'  make helm-validate        Validate Argo CD platform manifests' \
		'  make helm-deploy          Install Argo CD and bootstrap from git origin' \
		'  make helm-deploy-secrets  Apply local ignored Kubernetes secrets'

talos:
	@$(MAKE) -C "$(TALOS_DIR)" help

helm:
	@$(MAKE) -C "$(HELM_DIR)" help

helm-%:
	@$(MAKE) -C "$(HELM_DIR)" $*

%:
	@$(MAKE) -C "$(TALOS_DIR)" $@
