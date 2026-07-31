#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib.sh"

config="${1:?config file is required}"
action="${2:?action is required}"

load_ini "$config"
require_config CLUSTER_ENDPOINT_IP NODE_IP
require_cmd talosctl

case "$action" in
  reboot)
    run_talosctl reboot --drain
    ;;
  reboot-force)
    run_talosctl reboot --mode force
    ;;
  shutdown)
    run_talosctl shutdown
    ;;
  shutdown-force)
    run_talosctl shutdown --force
    ;;
  *)
    printf 'Usage: %s <config.ini> {reboot|reboot-force|shutdown|shutdown-force}\n' "$0" >&2
    exit 1
    ;;
esac
