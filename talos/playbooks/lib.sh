#!/usr/bin/env bash
set -euo pipefail

repo_root() {
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd
}

load_ini() {
  local config_file="${1:?config file is required}"

  if [[ ! -f "$config_file" ]]; then
    printf 'Missing config file: %s\n' "$config_file" >&2
    exit 1
  fi

  eval "$(
    awk '
      function trim(value) {
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)
        return value
      }
      /^[[:space:]]*($|[#;])/ { next }
      /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
        section = toupper($0)
        gsub(/^[[:space:]]*\[/, "", section)
        gsub(/\][[:space:]]*$/, "", section)
        gsub(/[^A-Z0-9_]/, "_", section)
        next
      }
      /^[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*=/ {
        split($0, parts, "=")
        key = trim(parts[1])
        value = substr($0, index($0, "=") + 1)
        value = trim(value)
        gsub(/[^A-Za-z0-9_]/, "_", key)
        key = toupper(key)
        if (section != "") {
          key = section "_" key
        }
        gsub(/\047/, "'\''\\'\''\047", value)
        printf("%s='\''%s'\''\n", key, value)
      }
    ' "$config_file"
  )"
}

require_cmd() {
  local cmd="${1:?command is required}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$cmd" >&2
    exit 1
  fi
}

require_config() {
  local missing=0
  for name in "$@"; do
    if [[ -z "${!name:-}" ]]; then
      printf 'Missing required ini value: %s\n' "$name" >&2
      missing=1
    fi
  done
  if [[ "$missing" -ne 0 ]]; then
    exit 1
  fi
}

cluster_endpoint() {
  printf 'https://%s:%s' "$CLUSTER_ENDPOINT_IP" "$CLUSTER_ENDPOINT_PORT"
}

talos_config_path() {
  printf '%s/manifests/talosconfig' "$(repo_root)"
}

controlplane_config_path() {
  printf '%s/manifests/controlplane.yaml' "$(repo_root)"
}

run_talosctl() {
  talosctl --talosconfig "$(talos_config_path)" \
    --endpoints "$CLUSTER_ENDPOINT_IP" \
    --nodes "$NODE_IP" \
    "$@"
}
