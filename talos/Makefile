SHELL := bash

CONFIG ?= cluster.ini

.DEFAULT_GOAL := help

.PHONY: help check netcheck status secrets config validate apply apply-auth apply-auth-confirm bootstrap kubeconfig install-configs disks disks-auth dashboard health talosconfig talosconfig-install clean-manifests

help:
	@printf '%s\n' \
		'Targets:' \
		'  make check            Check local tool availability and parsed cluster.ini' \
		'  make netcheck         Check local route and Talos API port reachability' \
		'  make status           Query Talos maintenance API status' \
		'  make secrets          Generate ./secrets/talos-secrets.yaml' \
		'  make config           Build Talos manifests from patches/*.yaml' \
		'  make validate         Validate control plane config for metal mode' \
		'  make disks            List disks over the insecure maintenance API' \
		'  make disks-auth       List disks using repo talosconfig after install' \
		'  make apply            Apply control plane config to the node in maintenance mode' \
		'  make apply-auth       Apply control plane config using authenticated Talos API' \
		'  make apply-auth-confirm  Confirm authenticated Talos config without reboot' \
		'  make bootstrap        Bootstrap the single-node control plane' \
		'  make kubeconfig       Merge Kubernetes kubeconfig into ~/.kube/config' \
		'  make install-configs  Install talosconfig and kubeconfig into home' \
		'  make dashboard        Open talosctl dashboard' \
		'  make health           Run talosctl health' \
		'  make talosconfig      Print TALOSCONFIG path for this repo' \
		'  make talosconfig-install  Install talosconfig into ~/.talos/config' \
		'' \
		'Variables:' \
		'  CONFIG=cluster.ini    Path to cluster ini file'

check:
	@playbooks/check.sh "$(CONFIG)"

netcheck:
	@playbooks/talos.sh "$(CONFIG)" netcheck

status:
	@playbooks/talos.sh "$(CONFIG)" status

secrets:
	@playbooks/secrets.sh "$(CONFIG)"

config: secrets
	@playbooks/config.sh "$(CONFIG)"

validate: config
	@talosctl validate --mode metal --strict --config manifests/controlplane.yaml

apply: config
	@playbooks/apply.sh "$(CONFIG)"

apply-auth: config
	@talosctl --talosconfig manifests/talosconfig \
		--endpoints "$$(awk -F= '/^[[:space:]]*endpoint_ip[[:space:]]*=/{gsub(/[[:space:]]/, "", $$2); print $$2}' "$(CONFIG)")" \
		--nodes "$$(awk -F= '/^[[:space:]]*ip[[:space:]]*=/{gsub(/[[:space:]]/, "", $$2); print $$2}' "$(CONFIG)")" \
		apply-config --mode try --timeout 2m --file manifests/controlplane.yaml

apply-auth-confirm: config
	@talosctl --talosconfig manifests/talosconfig \
		--endpoints "$$(awk -F= '/^[[:space:]]*endpoint_ip[[:space:]]*=/{gsub(/[[:space:]]/, "", $$2); print $$2}' "$(CONFIG)")" \
		--nodes "$$(awk -F= '/^[[:space:]]*ip[[:space:]]*=/{gsub(/[[:space:]]/, "", $$2); print $$2}' "$(CONFIG)")" \
		apply-config --mode no-reboot --file manifests/controlplane.yaml

bootstrap:
	@playbooks/bootstrap.sh "$(CONFIG)"

kubeconfig:
	@playbooks/kubeconfig.sh "$(CONFIG)"

install-configs: talosconfig-install kubeconfig

disks:
	@playbooks/talos.sh "$(CONFIG)" disks

disks-auth:
	@playbooks/talos.sh "$(CONFIG)" disks-auth

dashboard:
	@playbooks/talos.sh "$(CONFIG)" dashboard

health:
	@playbooks/talos.sh "$(CONFIG)" health

talosconfig:
	@printf '%s\n' "$$(pwd)/manifests/talosconfig"

talosconfig-install: config
	@playbooks/talosconfig-install.sh "$(CONFIG)"

clean-manifests:
	@rm -rf manifests
