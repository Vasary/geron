SHELL := bash

TALOS_DIR := talos

.DEFAULT_GOAL := help

.PHONY: help talos helm

help:
	@$(MAKE) -C "$(TALOS_DIR)" help
	@printf '%s\n' \
		'' \
		'Structure:' \
		'  talos/   Talos configs, patches, scripts, generated manifests, secrets' \
		'  helm/    Future cluster add-ons and Helm releases'

talos:
	@$(MAKE) -C "$(TALOS_DIR)" help

helm:
	@printf '%s\n' 'helm/ is reserved for future cluster add-ons and Helm releases.'

%:
	@$(MAKE) -C "$(TALOS_DIR)" $@
