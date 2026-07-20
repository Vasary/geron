#!/usr/bin/env bash
set -euo pipefail

sops_only=false
if [ "${1:-}" = "--sops-only" ]; then
  sops_only=true
  shift
fi

secret_file="${1:-secrets/authentik.sops.yaml}"
admin_user="${2:-akadmin}"
age_key_file="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
helm_dir="$(cd -- "$script_dir/.." && pwd)"
repo_root="$(cd -- "$helm_dir/.." && pwd)"
sops_config="${SOPS_CONFIG:-$repo_root/.sops.yaml}"
secret_rel_to_helm="${secret_file#./}"
secret_rel_to_repo="helm/$secret_rel_to_helm"
secret_output="$helm_dir/$secret_rel_to_helm"

case "$admin_user" in
  *[!A-Za-z0-9_.@+-]*)
    printf 'Unsupported Authentik username: %s\n' "$admin_user" >&2
    exit 1
    ;;
esac

command -v sops >/dev/null || {
  printf '%s\n' 'Missing sops.' >&2
  exit 1
}

command -v jq >/dev/null || {
  printf '%s\n' 'Missing jq.' >&2
  exit 1
}

if [ "$sops_only" = false ]; then
  command -v kubectl >/dev/null || {
    printf '%s\n' 'Missing kubectl.' >&2
    exit 1
  }
fi

test -f "$age_key_file" || {
  printf 'Missing SOPS age key: %s\n' "$age_key_file" >&2
  exit 1
}

test -f "$sops_config" || {
  printf 'Missing SOPS config: %s\n' "$sops_config" >&2
  exit 1
}

test -f "$secret_output" || {
  printf 'Missing Authentik SOPS secret: %s\n' "$secret_rel_to_repo" >&2
  exit 1
}

printf 'New Authentik admin password for %s: ' "$admin_user"
IFS= read -rs password
printf '\nRepeat password: '
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

printf '%s' "$password" | jq -Rs . | SOPS_AGE_KEY_FILE="$age_key_file" sops \
  --config "$sops_config" \
  --filename-override "$secret_rel_to_repo" \
  --value-stdin \
  set "$secret_output" '["stringData"]["AUTHENTIK_BOOTSTRAP_PASSWORD"]'

printf 'Wrote %s\n' "$secret_rel_to_repo"

if [ "$sops_only" = true ]; then
  printf '%s\n' 'Updated bootstrap password only. Existing Authentik users are not changed until you reset them live.'
  printf '%s\n' 'Run make authentik-password to also reset the live admin user.'
  exit 0
fi

printf 'Resetting live Authentik password for %s...\n' "$admin_user"
printf '%s' "$password" | kubectl -n authentik exec -i deploy/authentik-worker -- ak shell -c "
import sys
from authentik.core.models import User

username = '$admin_user'
password = sys.stdin.read()
user = User.objects.get(username=username)
user.set_password(password)
user.save()
print(f'Updated live Authentik password for {username}')
"

printf '%s\n' 'Run make deploy-secrets to apply the encrypted bootstrap secret as well.'
