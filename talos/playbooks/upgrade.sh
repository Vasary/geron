#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
source ./lib.sh

config_file="${1:-cluster.ini}"
load_ini "$config_file"
require_config CLUSTER_NAME CLUSTER_ENDPOINT_IP NODE_NAME NODE_IP
require_cmd talosctl

talosconfig="$(talos_config_path)"
if [[ ! -f "$talosconfig" ]]; then
  printf 'Missing %s. Run make config first.\n' "$talosconfig" >&2
  exit 1
fi

printf 'Talos node: %s (%s)\n' "$NODE_NAME" "$NODE_IP"
printf 'Cluster endpoint: %s\n' "$CLUSTER_ENDPOINT_IP"
printf '\nCurrent version:\n'
version_output="$(run_talosctl version --short)"
printf '%s\n' "$version_output"
current_version="$(
  awk '
    $1 == "Server:" { server = 1; next }
    server && $1 == "Tag:" { print $2; exit }
  ' <<<"$version_output"
)"

if [[ -z "$current_version" ]]; then
  printf 'Unable to detect current Talos server version.\n' >&2
  exit 1
fi

printf '\nEnter Talos version to install, for example v1.10.5: '
read -r version
version="${version//[[:space:]]/}"

if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]]; then
  printf 'Invalid Talos version: %s\n' "$version" >&2
  printf 'Expected format like v1.10.5\n' >&2
  exit 1
fi

require_adjacent_minor_upgrade "Talos" "$current_version" "$version"

image="ghcr.io/siderolabs/installer:${version}"

printf '\nThis will upgrade Talos on %s (%s) using:\n  %s\n' "$NODE_NAME" "$NODE_IP" "$image"
printf 'The node will reboot during the upgrade.\n'
printf 'Type the target version again to continue: '
read -r confirmation

if [[ "$confirmation" != "$version" ]]; then
  printf 'Upgrade cancelled.\n'
  exit 1
fi

printf '\nSingle-node upgrade mode: Kubernetes drain is disabled because pods have no other node to move to.\n'
printf 'If the upgrade is interrupted after cordoning, recover scheduling with:\n'
printf '  kubectl uncordon %s\n\n' "$NODE_NAME"

run_talosctl upgrade --image "$image" --wait --timeout 1h --drain=false
