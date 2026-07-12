#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "$0")/lib.sh"

config="${1:-cluster.ini}"
cd "$(repo_root)"
load_ini "$config"

require_cmd talosctl
require_config \
  CLUSTER_NAME CLUSTER_ENDPOINT_IP CLUSTER_ENDPOINT_PORT NODE_NAME NODE_IP

printf 'talosctl: %s\n' "$(talosctl version --client --short 2>/dev/null || talosctl version --client)"
printf 'cluster:  %s\n' "$CLUSTER_NAME"
printf 'endpoint: %s\n' "$(cluster_endpoint)"
printf 'node:     %s (%s)\n' "$NODE_NAME" "$NODE_IP"
printf 'patches:  patches/controlplane/*.yaml\n'
