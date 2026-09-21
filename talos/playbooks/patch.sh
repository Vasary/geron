#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "$0")/lib.sh"

config="${1:-cluster.ini}"
patch_file="${2:?patch file is required}"

cd "$(repo_root)"
load_ini "$config"
require_cmd talosctl
require_config CLUSTER_ENDPOINT_IP NODE_IP

if [[ ! -f "$patch_file" ]]; then
  printf 'Missing patch file: %s\n' "$patch_file" >&2
  exit 1
fi

run_talosctl patch machineconfig --mode no-reboot --patch-file "$patch_file"
