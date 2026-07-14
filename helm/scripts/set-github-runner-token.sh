#!/usr/bin/env bash
set -euo pipefail

secret_file="${1:-secrets/github-runner-auth.sops.yaml}"
age_key_file="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
helm_dir="$(cd -- "$script_dir/.." && pwd)"
repo_root="$(cd -- "$helm_dir/.." && pwd)"
sops_config="${SOPS_CONFIG:-$repo_root/.sops.yaml}"
secret_rel_to_helm="${secret_file#./}"
secret_output="$helm_dir/$secret_rel_to_helm"

command -v sops >/dev/null || {
  printf '%s\n' 'Missing sops.' >&2
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

printf '%s' 'GitHub runner token: '
IFS= read -rs github_token
printf '\n'

if [ -z "$github_token" ]; then
  printf '%s\n' 'Token must not be empty.' >&2
  exit 1
fi

tmp_file="$(mktemp)"
encrypted_tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file" "$encrypted_tmp_file"' EXIT

cat >"$tmp_file" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: github-runner-auth
  namespace: arc-runners
  annotations:
    argocd.argoproj.io/sync-wave: "5"
type: Opaque
stringData:
  github_token: "$github_token"
EOF

SOPS_AGE_KEY_FILE="$age_key_file" sops \
  --config "$sops_config" \
  --filename-override "$secret_output" \
  --encrypt "$tmp_file" >"$encrypted_tmp_file"

mkdir -p "$(dirname "$secret_output")"
mv "$encrypted_tmp_file" "$secret_output"
printf 'Wrote %s\n' "helm/$secret_rel_to_helm"
printf '%s\n' 'Run make deploy-secrets to apply it.'
