#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "$0")/lib.sh"

config="${1:-cluster.ini}"
command_name="${2:-}"

cd "$(repo_root)"
load_ini "$config"

require_cmd talosctl
require_config CLUSTER_ENDPOINT_IP NODE_IP

case "$command_name" in
  netcheck)
    printf 'Route to %s:\n' "$NODE_IP"
    ip route get "$NODE_IP" || true
    if command -v tracepath >/dev/null 2>&1; then
      printf '\nTracepath to %s:\n' "$NODE_IP"
      tracepath -n "$NODE_IP" || true
    fi
    printf '\nPing %s:\n' "$NODE_IP"
    ping -c 2 -W 1 "$NODE_IP" || true
    printf '\nTalos maintenance API port %s:50000:\n' "$NODE_IP"
    nc -vz -w 3 "$NODE_IP" 50000
    ;;
  status)
    printf 'Talos maintenance API version on %s:\n' "$NODE_IP"
    talosctl version --insecure --endpoints "$NODE_IP" --nodes "$NODE_IP" --short
    printf '\nDisks:\n'
    talosctl get disks --insecure --endpoints "$NODE_IP" --nodes "$NODE_IP"
    printf '\nLinks:\n'
    talosctl get links --insecure --endpoints "$NODE_IP" --nodes "$NODE_IP" || true
    printf '\nAddress specs:\n'
    talosctl get addressspecs --insecure --endpoints "$NODE_IP" --nodes "$NODE_IP" || true
    printf '\nRoute specs:\n'
    talosctl get routespecs --insecure --endpoints "$NODE_IP" --nodes "$NODE_IP" || true
    printf '\nResolvers:\n'
    talosctl get resolvers --insecure --endpoints "$NODE_IP" --nodes "$NODE_IP" || true
    ;;
  disks)
    printf 'Listing disks via Talos maintenance API on %s.\n' "$NODE_IP"
    talosctl get disks --insecure --endpoints "$NODE_IP" --nodes "$NODE_IP"
    ;;
  disks-auth)
    run_talosctl disks
    ;;
  dashboard)
    printf 'Opening interactive talosctl dashboard. Press Ctrl-C to exit.\n'
    printf 'This works after Talos is installed/configured; maintenance mode has no authenticated Talos API yet.\n'
    run_talosctl dashboard
    ;;
  health)
    run_talosctl health
    ;;
  *)
    printf 'Usage: %s <config.ini> {netcheck|status|disks|disks-auth|dashboard|health}\n' "$0" >&2
    exit 1
    ;;
esac
