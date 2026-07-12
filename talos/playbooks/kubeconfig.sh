#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "$0")/lib.sh"

config="${1:-cluster.ini}"
root="$(repo_root)"
cd "$root"
load_ini "$config"

require_cmd talosctl
require_config CLUSTER_ENDPOINT_IP NODE_IP

kube_dir="${HOME:?HOME is not set}/.kube"
kube_config="$kube_dir/config"

mkdir -p "$kube_dir"
chmod 700 "$kube_dir"

if [[ -f "$kube_config" ]]; then
  backup="$kube_config.bak.$(date +%Y%m%d%H%M%S)"
  cp "$kube_config" "$backup"
  chmod 600 "$backup"
  printf 'Backed up existing kubeconfig to %s\n' "$backup"
fi

run_talosctl kubeconfig "$kube_config" \
  --merge \
  --force \
  --force-context-name "$CLUSTER_NAME"

chmod 600 "$kube_config"
printf 'Merged kubeconfig into %s\n' "$kube_config"
printf 'Try: kubectl --context %s get nodes\n' "$CLUSTER_NAME"
