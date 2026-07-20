#!/usr/bin/env bash
set -euo pipefail

secret_file="${1:-secrets/argocd.sops.yaml}"
age_key_file="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
helm_dir="$(cd -- "$script_dir/.." && pwd)"
repo_root="$(cd -- "$helm_dir/.." && pwd)"
sops_config="${SOPS_CONFIG:-$repo_root/.sops.yaml}"
secret_rel_to_helm="${secret_file#./}"
secret_rel_to_repo="helm/$secret_rel_to_helm"
secret_output="$helm_dir/$secret_rel_to_helm"

command -v mkpasswd >/dev/null || {
  printf '%s\n' 'Missing mkpasswd. Install whois/mkpasswd with bcrypt support.' >&2
  exit 1
}

command -v sops >/dev/null || {
  printf '%s\n' 'Missing sops.' >&2
  exit 1
}

command -v jq >/dev/null || {
  printf '%s\n' 'Missing jq.' >&2
  exit 1
}

test -f "$age_key_file" || {
  printf 'Missing SOPS age key: %s\n' "$age_key_file" >&2
  exit 1
}

test -f "$sops_config" || {
  printf 'Missing SOPS config: %s\n' "$sops_config" >&2
  exit 1
}

test -f "$secret_output" || {
  printf 'Missing Argo CD SOPS secret: %s\n' "$secret_rel_to_repo" >&2
  exit 1
}

printf '%s' 'New Argo CD admin password: '
IFS= read -rs password
printf '\n%s' 'Repeat password: '
IFS= read -rs password_confirm
printf '\n'

if [ -z "$password" ]; then
  printf '%s\n' 'Password must not be empty.' >&2
  exit 1
fi

if [ "$password" != "$password_confirm" ]; then
  printf '%s\n' 'Passwords do not match.' >&2
  exit 1
fi

password_hash="$(printf '%s' "$password" | mkpasswd -m bcrypt -s)"
password_mtime="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

SOPS_AGE_KEY_FILE="$age_key_file" sops \
  --config "$sops_config" \
  --filename-override "$secret_rel_to_repo" \
  set "$secret_output" '["stringData"]["admin.password"]' "$(jq -Rn --arg value "$password_hash" '$value')"

SOPS_AGE_KEY_FILE="$age_key_file" sops \
  --config "$sops_config" \
  --filename-override "$secret_rel_to_repo" \
  set "$secret_output" '["stringData"]["admin.passwordMtime"]' "$(jq -Rn --arg value "$password_mtime" '$value')"

printf 'Wrote %s\n' "$secret_rel_to_repo"
printf '%s\n' 'Run make deploy-secrets to apply it.'
