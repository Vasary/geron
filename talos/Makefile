SHELL := bash

CONFIG ?= cluster.ini

.DEFAULT_GOAL := help

.PHONY: help check netcheck status secrets config validate apply apply-try apply-no-reboot apply-auth apply-auth-confirm bootstrap kubeconfig install-configs disks disks-auth dashboard health upgrade upgrade-k8s reboot reboot-force shutdown shutdown-force talosconfig talosconfig-install clean-manifests

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
		'  make apply-try        Apply authenticated config in try mode with auto-rollback' \
		'  make apply-no-reboot  Apply authenticated config without reboot' \
		'  make bootstrap        Bootstrap the single-node control plane' \
		'  make kubeconfig       Merge Kubernetes kubeconfig into ~/.kube/config' \
		'  make install-configs  Install talosconfig and kubeconfig into home' \
		'  make dashboard        Open talosctl dashboard' \
		'  make health           Run talosctl health' \
		'  make upgrade          Interactively upgrade Talos OS on the node' \
		'  make upgrade-k8s      Interactively upgrade Kubernetes via Talos' \
		'  make reboot           Drain and reboot the Talos node' \
		'  make reboot-force     Reboot the Talos node without drain' \
		'  make shutdown         Drain and shut down the Talos node' \
		'  make shutdown-force   Shut down the Talos node without drain' \
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

apply-try: config
	@talosctl --talosconfig manifests/talosconfig \
		--endpoints "$$(awk -F= '/^[[:space:]]*endpoint_ip[[:space:]]*=/{gsub(/[[:space:]]/, "", $$2); print $$2}' "$(CONFIG)")" \
		--nodes "$$(awk -F= '/^[[:space:]]*ip[[:space:]]*=/{gsub(/[[:space:]]/, "", $$2); print $$2}' "$(CONFIG)")" \
		apply-config --mode try --timeout 2m --file manifests/controlplane.yaml

apply-no-reboot: config
	@talosctl --talosconfig manifests/talosconfig \
		--endpoints "$$(awk -F= '/^[[:space:]]*endpoint_ip[[:space:]]*=/{gsub(/[[:space:]]/, "", $$2); print $$2}' "$(CONFIG)")" \
		--nodes "$$(awk -F= '/^[[:space:]]*ip[[:space:]]*=/{gsub(/[[:space:]]/, "", $$2); print $$2}' "$(CONFIG)")" \
		apply-config --mode no-reboot --file manifests/controlplane.yaml

apply-auth:
	@printf 'Deprecated: use make apply-try instead.\n'
	@$(MAKE) apply-try CONFIG="$(CONFIG)"

apply-auth-confirm:
	@printf 'Deprecated: use make apply-no-reboot instead.\n'
	@$(MAKE) apply-no-reboot CONFIG="$(CONFIG)"

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

upgrade:
	@playbooks/upgrade.sh "$(CONFIG)"

upgrade-k8s:
	@playbooks/upgrade-k8s.sh "$(CONFIG)"

reboot:
	@playbooks/node-action.sh "$(CONFIG)" reboot

reboot-force:
	@playbooks/node-action.sh "$(CONFIG)" reboot-force

shutdown:
	@playbooks/node-action.sh "$(CONFIG)" shutdown

shutdown-force:
	@playbooks/node-action.sh "$(CONFIG)" shutdown-force

talosconfig:
	@printf '%s\n' "$$(pwd)/manifests/talosconfig"

talosconfig-install: config
	@playbooks/talosconfig-install.sh "$(CONFIG)"

clean-manifests:
	@rm -rf manifests
