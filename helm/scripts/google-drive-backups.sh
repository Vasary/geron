#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
helm_dir="$(cd -- "$script_dir/.." && pwd)"
secret_file="${BACKUP_SECRET_FILE:-$helm_dir/secrets/sftp-backup.sops.yaml}"

usage() {
  cat <<'EOF'
Usage:
  google-drive-backups.sh
  google-drive-backups.sh list [remote-path]
  google-drive-backups.sh download <remote-path> [local-directory]

Examples:
  google-drive-backups.sh
  google-drive-backups.sh list
  google-drive-backups.sh list outline
  google-drive-backups.sh download outline/outline-20261120T190726Z.sql.gz
  google-drive-backups.sh download paperless/export-20261120T031000Z ./restore
EOF
}

for command_name in sops yq jq rclone; do
  command -v "$command_name" >/dev/null || {
    printf 'Missing command: %s\n' "$command_name" >&2
    exit 1
  }
done

if [[ ! -f "$secret_file" ]]; then
  printf 'SOPS secret not found: %s\n' "$secret_file" >&2
  exit 1
fi

secret_json="$({
  SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}" \
    sops --decrypt "$secret_file"
} | yq -c 'select(.metadata.namespace == "authentik") | .stringData')"

if [[ -z "$secret_json" ]]; then
  printf 'Could not read Google Drive credentials from %s\n' "$secret_file" >&2
  exit 1
fi

export RCLONE_CONFIG="$(mktemp "${TMPDIR:-/tmp}/geron-google-drive-backups.XXXXXX.conf")"
trap 'rm -f "$RCLONE_CONFIG"' EXIT
export RCLONE_CONFIG_GDRIVE_TYPE=drive
export RCLONE_CONFIG_GDRIVE_CLIENT_ID="$(jq -r '.GOOGLE_DRIVE_CLIENT_ID' <<<"$secret_json")"
export RCLONE_CONFIG_GDRIVE_CLIENT_SECRET="$(jq -r '.GOOGLE_DRIVE_CLIENT_SECRET' <<<"$secret_json")"
export RCLONE_CONFIG_GDRIVE_TOKEN="$(jq -r '.GOOGLE_DRIVE_TOKEN' <<<"$secret_json")"
export RCLONE_CONFIG_GDRIVE_SCOPE=drive.file
export RCLONE_CONFIG_ENCRYPTED_TYPE=crypt
export RCLONE_CONFIG_ENCRYPTED_REMOTE="gdrive:${BACKUP_GOOGLE_DRIVE_PATH:-geron-backups}"
export RCLONE_CONFIG_ENCRYPTED_PASSWORD="$(rclone obscure "$(jq -r '.BACKUP_CRYPT_PASSWORD' <<<"$secret_json")")"
export RCLONE_CONFIG_ENCRYPTED_PASSWORD2="$(rclone obscure "$(jq -r '.BACKUP_CRYPT_SALT' <<<"$secret_json")")"
export RCLONE_CONFIG_ENCRYPTED_FILENAME_ENCRYPTION=standard
export RCLONE_CONFIG_ENCRYPTED_DIRECTORY_NAME_ENCRYPTION=true
unset secret_json

download_backup() {
  local kind="$1"
  local remote_path="$2"
  local local_directory="$3"

  mkdir -p "$local_directory"
  if [[ "$kind" == file ]]; then
    local local_file="$local_directory/$(basename -- "$remote_path")"
    rclone copyto "encrypted:$remote_path" "$local_file" --progress
    printf 'Decrypted file saved to: %s\n' "$local_file"
  else
    local target_directory="$local_directory/$(basename -- "${remote_path%/}")"
    mkdir -p "$target_directory"
    rclone copy "encrypted:${remote_path%/}" "$target_directory" --progress
    printf 'Decrypted directory saved to: %s\n' "$target_directory"
  fi
}

interactive_restore() {
  local default_directory="${BACKUP_RESTORE_DIR:-$PWD/restored-backups}"
  local current_path= destination directory file selection selected_index selected_kind selected_path
  local -a directories=() files=() labels=() kinds=() paths=()

  while true; do
    mapfile -t directories < <(
      rclone lsf "encrypted:$current_path" --max-depth 1 --dirs-only | sed 's#/$##' | sort
    )
    mapfile -t files < <(
      rclone lsf "encrypted:$current_path" --max-depth 1 --files-only | sort
    )
    labels=()
    kinds=()
    paths=()

    if [[ -n "$current_path" ]]; then
      labels+=("[DOWNLOAD THIS DIRECTORY] $current_path" "[..] Go up")
      kinds+=(download-directory up)
      paths+=("$current_path" "")
    fi
    for directory in "${directories[@]}"; do
      labels+=("[DIR] $directory")
      kinds+=(directory)
      paths+=("${current_path:+$current_path/}$directory")
    done
    for file in "${files[@]}"; do
      labels+=("[FILE] $file")
      kinds+=(file)
      paths+=("${current_path:+$current_path/}$file")
    done
    labels+=("[QUIT]")
    kinds+=(quit)
    paths+=("")

    printf '\nCurrent Google Drive backup path: /%s\n' "$current_path"
    PS3='Select number: '
    select selection in "${labels[@]}"; do
      if [[ "$REPLY" =~ ^[0-9]+$ ]] && (( REPLY >= 1 && REPLY <= ${#labels[@]} )); then
        selected_index=$((REPLY - 1))
        selected_kind="${kinds[$selected_index]}"
        selected_path="${paths[$selected_index]}"
        break
      fi
      printf 'Invalid selection.\n' >&2
    done

    case "$selected_kind" in
      directory)
        current_path="$selected_path"
        ;;
      up)
        current_path="$(dirname -- "$current_path")"
        [[ "$current_path" == . ]] && current_path=
        ;;
      file|download-directory)
        printf 'Selected: %s\n' "$selected_path"
        read -r -p "Destination directory [$default_directory]: " destination
        destination="${destination:-$default_directory}"
        if [[ "$selected_kind" == file ]]; then
          download_backup file "$selected_path" "$destination"
        else
          download_backup directory "$selected_path" "$destination"
        fi
        return 0
        ;;
      quit)
        return 0
        ;;
    esac
  done
}

action="${1:-interactive}"
case "$action" in
  interactive)
    interactive_restore
    ;;
  list)
    remote_path="${2:-}"
    rclone lsl "encrypted:$remote_path"
    ;;
  download)
    remote_path="${2:-}"
    local_directory="${3:-./restored-backups}"
    if [[ -z "$remote_path" ]]; then
      usage >&2
      exit 2
    fi
    remote_parent="$(dirname -- "$remote_path")"
    remote_name="$(basename -- "$remote_path")"
    if [[ "$remote_parent" == . ]]; then
      remote_parent=
    fi
    if rclone lsf "encrypted:$remote_parent" --files-only --max-depth 1 2>/dev/null | grep -Fxq "$remote_name"; then
      kind=file
    else
      kind=directory
    fi
    download_backup "$kind" "$remote_path" "$local_directory"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
