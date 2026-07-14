#!/usr/bin/env bash
set -euo pipefail

secret_file="${1:-secrets/hermes.sops.yaml}"
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

printf '%s' 'Telegram bot token: '
IFS= read -rs telegram_bot_token
printf '\n'
printf '%s' 'Telegram allowed users (comma-separated, optional): '
IFS= read -r telegram_allowed_users

if [ -z "$telegram_bot_token" ]; then
  printf '%s\n' 'Telegram bot token must not be empty.' >&2
  exit 1
fi

tmp_file="$(mktemp)"
encrypted_tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file" "$encrypted_tmp_file"' EXIT

cat >"$tmp_file" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: hermes-secrets
  namespace: hermes
  annotations:
    argocd.argoproj.io/sync-wave: "5"
type: Opaque
stringData:
  TELEGRAM_BOT_TOKEN: "$telegram_bot_token"
  TELEGRAM_ALLOWED_USERS: "$telegram_allowed_users"
EOF

SOPS_AGE_KEY_FILE="$age_key_file" sops \
  --config "$sops_config" \
  --filename-override "$secret_output" \
  --encrypt "$tmp_file" >"$encrypted_tmp_file"

mkdir -p "$(dirname "$secret_output")"
mv "$encrypted_tmp_file" "$secret_output"
printf 'Wrote %s\n' "helm/$secret_rel_to_helm"
printf '%s\n' 'Run make deploy-secrets to apply it.'
