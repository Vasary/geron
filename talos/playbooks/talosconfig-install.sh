#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "$0")/lib.sh"

config="${1:-cluster.ini}"
root="$(repo_root)"
cd "$root"
load_ini "$config"

source_config="$(talos_config_path)"
if [[ ! -f "$source_config" ]]; then
  printf 'Missing %s. Run make config first.\n' "$source_config" >&2
  exit 1
fi

talos_dir="${HOME:?HOME is not set}/.talos"
target_config="$talos_dir/config"

mkdir -p "$talos_dir"
chmod 700 "$talos_dir"

if [[ -f "$target_config" ]]; then
  backup="$target_config.bak.$(date +%Y%m%d%H%M%S)"
  cp "$target_config" "$backup"
  chmod 600 "$backup"
  printf 'Backed up existing talosconfig to %s\n' "$backup"
fi

cp "$source_config" "$target_config"
chmod 600 "$target_config"

printf 'Installed talosconfig into %s\n' "$target_config"
printf 'Try: talosctl version --nodes %s\n' "$NODE_IP"
