#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "$0")/lib.sh"

config="${1:-cluster.ini}"
cd "$(repo_root)"
load_ini "$config"

require_cmd talosctl
require_config CLUSTER_ENDPOINT_IP NODE_IP

machine_config="$(controlplane_config_path)"
if [[ ! -f "$machine_config" ]]; then
  printf 'Missing %s. Run make config first.\n' "$machine_config" >&2
  exit 1
fi

printf 'Applying Talos install config to %s over the insecure maintenance API.\n' "$NODE_IP"
printf 'Disk/network settings are taken from patches/controlplane/*.yaml.\n'

talosctl apply-config \
  --insecure \
  --endpoints "$NODE_IP" \
  --nodes "$NODE_IP" \
  --file "$machine_config"

printf 'Config applied. Wait for the node to install/reboot, then run make bootstrap.\n'
