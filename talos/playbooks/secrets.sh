#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "$0")/lib.sh"

config="${1:-cluster.ini}"
root="$(repo_root)"
cd "$root"
load_ini "$config"

require_cmd talosctl

mkdir -p "$root/secrets"
chmod 700 "$root/secrets"

secrets_file="$root/secrets/talos-secrets.yaml"
if [[ -f "$secrets_file" ]]; then
  printf 'Talos secrets already exist: %s\n' "$secrets_file"
  exit 0
fi

talosctl gen secrets --output-file "$secrets_file"
chmod 600 "$secrets_file"

printf 'Generated %s\n' "$secrets_file"
