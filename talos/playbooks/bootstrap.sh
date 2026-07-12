#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "$0")/lib.sh"

config="${1:-cluster.ini}"
cd "$(repo_root)"
load_ini "$config"

require_cmd talosctl
require_config CLUSTER_ENDPOINT_IP NODE_IP

talosconfig="$(talos_config_path)"
if [[ ! -f "$talosconfig" ]]; then
  printf 'Missing %s. Run make config first.\n' "$talosconfig" >&2
  exit 1
fi

printf 'Bootstrapping Kubernetes control plane on %s.\n' "$NODE_IP"
run_talosctl bootstrap

printf 'Merging kubeconfig into ~/.kube/config.\n'
"$(dirname -- "$0")/kubeconfig.sh" "$config"
