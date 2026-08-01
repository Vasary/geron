SHELL := bash

TALOS_DIR := talos
HELM_DIR := helm
FIRST_GOAL := $(firstword $(MAKECMDGOALS))
SUBCOMMANDS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
FORWARDED_SUBCOMMANDS := $(filter-out help talos helm,$(SUBCOMMANDS))

.DEFAULT_GOAL := help

.PHONY: help talos helm

help:
	@printf '%s\n' \
		'Usage:' \
		'  make talos [target]    Run a target from talos/Makefile' \
		'  make helm [target]     Run a target from helm/Makefile' \
		'' \
		'Examples:' \
		'  make talos config' \
		'  make talos apply-try' \
		'  make talos upgrade' \
		'  make talos upgrade-k8s' \
		'  make talos reboot' \
		'  make helm validate' \
		'  make helm deploy' \
		'  make helm deploy-secrets' \
		'' \
		'Without a nested target, make talos or make helm shows that Makefile help.'

talos:
	@$(MAKE) -C "$(TALOS_DIR)" $(SUBCOMMANDS)

helm:
	@$(MAKE) -C "$(HELM_DIR)" $(SUBCOMMANDS)

ifneq ($(filter talos helm,$(FIRST_GOAL)),)
$(eval .PHONY: $(FORWARDED_SUBCOMMANDS))
$(eval $(FORWARDED_SUBCOMMANDS):; @true)
endif
