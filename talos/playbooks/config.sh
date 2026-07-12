#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "$0")/lib.sh"

config="${1:-cluster.ini}"
root="$(repo_root)"
cd "$root"
load_ini "$config"

require_cmd talosctl
require_config \
  CLUSTER_NAME CLUSTER_ENDPOINT_IP CLUSTER_ENDPOINT_PORT NODE_NAME NODE_IP

manifest_dir="$root/manifests"
mkdir -p "$root/secrets" "$manifest_dir"
chmod 700 "$root/secrets" "$manifest_dir"

secrets_file="$root/secrets/talos-secrets.yaml"
if [[ ! -f "$secrets_file" ]]; then
  printf 'Missing %s. Run make secrets first.\n' "$secrets_file" >&2
  exit 1
fi

patch_dir="$root/patches/controlplane"
if [[ ! -d "$patch_dir" ]]; then
  printf 'Missing patch directory: %s\n' "$patch_dir" >&2
  exit 1
fi

mapfile -t patch_files < <(find "$patch_dir" -maxdepth 1 -type f -name '*.yaml' | sort)
if [[ "${#patch_files[@]}" -eq 0 ]]; then
  printf 'No patch files found in %s\n' "$patch_dir" >&2
  exit 1
fi

gen_args=(
  gen config
  "$CLUSTER_NAME"
  "$(cluster_endpoint)"
  --with-secrets "$secrets_file"
  --output "$manifest_dir"
  --output-types controlplane,talosconfig
  --force
  --with-docs=false
  --with-examples=false
)

for patch_file in "${patch_files[@]}"; do
  gen_args+=(--config-patch-control-plane "@$patch_file")
done

talosctl "${gen_args[@]}"
chmod 600 "$manifest_dir/controlplane.yaml" "$manifest_dir/talosconfig"

talosctl --talosconfig "$manifest_dir/talosconfig" config endpoint "$CLUSTER_ENDPOINT_IP"
talosctl --talosconfig "$manifest_dir/talosconfig" config node "$NODE_IP"

printf 'Wrote Talos manifests in %s\n' "$manifest_dir"
printf 'Talos endpoints: %s\n' "$CLUSTER_ENDPOINT_IP"
printf 'Talos nodes: %s\n' "$NODE_IP"
printf 'Applied control plane patches:\n'
printf '  %s\n' "${patch_files[@]#$root/}"
