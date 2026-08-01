#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
source ./lib.sh

config_file="${1:-cluster.ini}"
load_ini "$config_file"
require_config CLUSTER_NAME CLUSTER_ENDPOINT_IP NODE_NAME NODE_IP
require_cmd talosctl
require_cmd kubectl

talosconfig="$(talos_config_path)"
if [[ ! -f "$talosconfig" ]]; then
  printf 'Missing %s. Run make config first.\n' "$talosconfig" >&2
  exit 1
fi

current_version="$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}')"
if [[ -z "$current_version" ]]; then
  printf 'Unable to detect current Kubernetes version from node status.\n' >&2
  exit 1
fi

printf 'Kubernetes node: %s (%s)\n' "$NODE_NAME" "$NODE_IP"
printf 'Current Kubernetes version: %s\n' "$current_version"
printf '\nEnter Kubernetes version to install, for example v1.36.3: '
read -r version
version="${version//[[:space:]]/}"

if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]]; then
  printf 'Invalid Kubernetes version: %s\n' "$version" >&2
  printf 'Expected format like v1.36.3\n' >&2
  exit 1
fi

require_adjacent_minor_upgrade "Kubernetes" "$current_version" "$version"

printf '\nDry-run upgrade plan for Kubernetes %s -> %s:\n' "$current_version" "$version"
run_talosctl upgrade-k8s --to "$version" --dry-run

printf '\nThis will upgrade Kubernetes control plane components, kube-proxy, kubelet, and Talos bootstrap manifests.\n'
printf 'Type the target version again to continue: '
read -r confirmation

if [[ "$confirmation" != "$version" ]]; then
  printf 'Kubernetes upgrade cancelled.\n'
  exit 1
fi

run_talosctl upgrade-k8s --to "$version"
