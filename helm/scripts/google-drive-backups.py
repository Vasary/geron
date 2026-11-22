#!/usr/bin/env python3
"""Browse, download, decrypt, and unpack Geron Google Drive backups."""

from __future__ import annotations

import argparse
import bz2
import gzip
import json
import lzma
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile

TOOLS = ("sops", "yq", "rclone")
CREDENTIALS = ("GOOGLE_DRIVE_CLIENT_ID", "GOOGLE_DRIVE_CLIENT_SECRET", "GOOGLE_DRIVE_TOKEN", "BACKUP_CRYPT_PASSWORD", "BACKUP_CRYPT_SALT")
TAR_SUFFIXES = (".tar.gz", ".tgz", ".tar.bz2", ".tbz2", ".tar.xz", ".txz", ".tar")
ARCHIVE_SUFFIXES = TAR_SUFFIXES + (".zip", ".gz", ".bz2", ".xz")


class BackupError(RuntimeError):
    """An error that can be shown directly to the user."""


def run(command: list[str], *, env: dict[str, str] | None = None, capture: bool = True) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(command, env=env, check=True, text=True,
                              stdout=subprocess.PIPE if capture else None,
                              stderr=subprocess.PIPE if capture else None)
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or error.stdout or str(error)).strip()
        raise BackupError(detail) from error


def check_tools() -> None:
    missing = [name for name in TOOLS if shutil.which(name) is None]
    if missing:
        raise BackupError(f"Missing required command(s): {', '.join(missing)}")


def load_credentials(secret_file: Path) -> dict[str, str]:
    if not secret_file.is_file():
        raise BackupError(f"SOPS secret not found: {secret_file}")
    decrypt_env = os.environ.copy()
    decrypt_env.setdefault("SOPS_AGE_KEY_FILE", str(Path.home() / ".config/sops/age/keys.txt"))
    decrypted = run(["sops", "--decrypt", str(secret_file)], env=decrypt_env).stdout
    query = 'select(.metadata.namespace == "authentik") | .stringData'
    try:
        result = subprocess.run(["yq", "-c", query], input=decrypted, check=True, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as error:
        raise BackupError((error.stderr or "Could not parse the SOPS secret").strip()) from error
    lines = [line for line in result.stdout.splitlines() if line and line != "null"]
    if not lines:
        raise BackupError(f"No authentik backup credentials found in {secret_file}")
    credentials = json.loads(lines[0])
    missing = [name for name in CREDENTIALS if not credentials.get(name)]
    if missing:
        raise BackupError(f"Incomplete backup credentials: {', '.join(missing)}")
    return credentials


def rclone_environment(credentials: dict[str, str], config_file: Path) -> dict[str, str]:
    env = os.environ.copy()
    env.update({
        "RCLONE_CONFIG": str(config_file),
        "RCLONE_CONFIG_GDRIVE_TYPE": "drive",
        "RCLONE_CONFIG_GDRIVE_CLIENT_ID": credentials["GOOGLE_DRIVE_CLIENT_ID"],
        "RCLONE_CONFIG_GDRIVE_CLIENT_SECRET": credentials["GOOGLE_DRIVE_CLIENT_SECRET"],
        "RCLONE_CONFIG_GDRIVE_TOKEN": credentials["GOOGLE_DRIVE_TOKEN"],
        "RCLONE_CONFIG_GDRIVE_SCOPE": "drive.file",
        "RCLONE_CONFIG_ENCRYPTED_TYPE": "crypt",
        "RCLONE_CONFIG_ENCRYPTED_REMOTE": f"gdrive:{env.get('BACKUP_GOOGLE_DRIVE_PATH', 'geron-backups')}",
        "RCLONE_CONFIG_ENCRYPTED_PASSWORD": run(["rclone", "obscure", credentials["BACKUP_CRYPT_PASSWORD"]]).stdout.strip(),
        "RCLONE_CONFIG_ENCRYPTED_PASSWORD2": run(["rclone", "obscure", credentials["BACKUP_CRYPT_SALT"]]).stdout.strip(),
        "RCLONE_CONFIG_ENCRYPTED_FILENAME_ENCRYPTION": "standard",
        "RCLONE_CONFIG_ENCRYPTED_DIRECTORY_NAME_ENCRYPTION": "true",
    })
    if credentials.get("GOOGLE_DRIVE_ROOT_FOLDER_ID"):
        env["RCLONE_CONFIG_GDRIVE_ROOT_FOLDER_ID"] = credentials["GOOGLE_DRIVE_ROOT_FOLDER_ID"]
    return env


def remote(path: str = "") -> str:
    return f"encrypted:{path.strip('/')}"


def list_directory(path: str, env: dict[str, str]) -> list[dict[str, object]]:
    output = run(["rclone", "lsjson", remote(path), "--max-depth", "1"], env=env).stdout
    return sorted(json.loads(output), key=lambda item: (not bool(item["IsDir"]), str(item["Name"]).casefold()))


def human_size(value: int) -> str:
    size = float(value)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if size < 1024 or unit == "TiB":
            return f"{size:.0f} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} TiB"


def child_path(parent: str, name: str) -> str:
    return str(PurePosixPath(parent) / name) if parent else name


def download(path: str, is_directory: bool, destination: Path, env: dict[str, str]) -> Path:
    destination.mkdir(parents=True, exist_ok=True)
    target = destination / PurePosixPath(path.rstrip("/")).name
    command = ["rclone", "copy" if is_directory else "copyto", remote(path), str(target), "--progress"]
    if is_directory:
        target.mkdir(parents=True, exist_ok=True)
    run(command, env=env, capture=False)
    return target


def _safe_members(names: list[str], destination: Path) -> None:
    root = destination.resolve()
    for name in names:
        candidate = (destination / name).resolve()
        if candidate != root and root not in candidate.parents:
            raise BackupError(f"Unsafe archive path: {name}")


def _without_archive_suffix(path: Path, suffixes: tuple[str, ...]) -> Path:
    lower = path.name.lower()
    suffix = next(item for item in suffixes if lower.endswith(item))
    return path.parent / path.name[:-len(suffix)]


def unpack_archive(path: Path) -> Path | None:
    lower = path.name.lower()
    if not lower.endswith(ARCHIVE_SUFFIXES):
        return None
    if lower.endswith(TAR_SUFFIXES):
        destination = _without_archive_suffix(path, TAR_SUFFIXES)
        destination.mkdir(parents=True, exist_ok=True)
        with tarfile.open(path) as archive:
            _safe_members(archive.getnames(), destination)
            archive.extractall(destination, filter="data")
        return destination
    if lower.endswith(".zip"):
        destination = path.with_suffix("")
        destination.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(path) as archive:
            _safe_members(archive.namelist(), destination)
            archive.extractall(destination)
        return destination
    opener = gzip.open if lower.endswith(".gz") else bz2.open if lower.endswith(".bz2") else lzma.open
    destination = path.with_suffix("")
    with opener(path, "rb") as source, destination.open("wb") as output:
        shutil.copyfileobj(source, output)
    return destination


def unpack_download(target: Path) -> list[Path]:
    candidates = [target] if target.is_file() else [item for item in target.rglob("*") if item.is_file()]
    unpacked = []
    for candidate in candidates:
        result = unpack_archive(candidate)
        if result:
            unpacked.append(result)
    return unpacked


def restore(path: str, is_directory: bool, default_destination: Path, env: dict[str, str]) -> None:
    answer = input(f"Destination directory [{default_destination}]: ").strip()
    destination = Path(answer).expanduser() if answer else default_destination
    target = download(path, is_directory, destination, env)
    print(f"\nDownloaded and decrypted: {target}")
    if input("Unpack archives now? [y/N]: ").strip().lower() in {"y", "yes"}:
        unpacked = unpack_download(target)
        print("Unpacked: " + ", ".join(map(str, unpacked)) if unpacked else "No supported archives found.")


def interactive(default_destination: Path, env: dict[str, str]) -> None:
    current = ""
    while True:
        entries = list_directory(current, env)
        print("\n" + "=" * 78)
        print(f"Google Drive backups  /{current}")
        print("=" * 78)
        if not entries:
            print("  (empty directory)")
        for index, item in enumerate(entries, 1):
            marker = "DIR " if item["IsDir"] else "FILE"
            size = "" if item["IsDir"] else human_size(int(item.get("Size", 0)))
            modified = str(item.get("ModTime", ""))[:16].replace("T", " ")
            branch = "└──" if index == len(entries) else "├──"
            print(f"{index:>3}. {branch} [{marker}] {str(item['Name']):<38.38} {size:>10}  {modified}")
        print("\nnumber=open/download | d=download this directory | u=up | r=refresh | q=quit")
        choice = input("> ").strip().lower()
        if choice == "q":
            return
        if choice == "r":
            continue
        if choice == "u":
            current = str(PurePosixPath(current).parent)
            current = "" if current == "." else current
            continue
        if choice == "d":
            if not current:
                print("Choose a directory first; downloading the entire backup root is disabled.")
            else:
                restore(current, True, default_destination, env)
            continue
        if choice.isdigit() and 1 <= int(choice) <= len(entries):
            selected = entries[int(choice) - 1]
            selected_path = child_path(current, str(selected["Name"]))
            if selected["IsDir"]:
                current = selected_path
            else:
                restore(selected_path, False, default_destination, env)
            continue
        print("Invalid command. Enter one of the commands shown above.")


def make_parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    subparsers = result.add_subparsers(dest="action")
    listing = subparsers.add_parser("list", help="list a remote directory")
    listing.add_argument("remote_path", nargs="?", default="")
    downloading = subparsers.add_parser("download", help="download and decrypt a file or directory")
    downloading.add_argument("remote_path")
    downloading.add_argument("local_directory", nargs="?", default="./restored-backups")
    downloading.add_argument("--extract", action="store_true", help="unpack supported archives after download")
    return result


def main() -> int:
    args = make_parser().parse_args()
    script_dir = Path(__file__).resolve().parent
    secret_file = Path(os.environ.get("BACKUP_SECRET_FILE", script_dir.parent / "secrets/sftp-backup.sops.yaml"))
    try:
        check_tools()
        print(f"Checking credentials in {secret_file} ...", flush=True)
        credentials = load_credentials(secret_file)
        with tempfile.NamedTemporaryFile(prefix="geron-google-drive-", suffix=".conf") as config:
            env = rclone_environment(credentials, Path(config.name))
            print("Checking Google Drive connection ...", flush=True)
            root_entries = list_directory("", env)
            print("Credentials and connection are OK.")
            if args.action == "list":
                entries = root_entries if not args.remote_path else list_directory(args.remote_path, env)
                for item in entries:
                    print(f"{item['Name']}{'/' if item['IsDir'] else ''}")
            elif args.action == "download":
                parent = str(PurePosixPath(args.remote_path).parent)
                parent = "" if parent == "." else parent
                name = PurePosixPath(args.remote_path).name
                matches = [item for item in list_directory(parent, env) if item["Name"] == name]
                if not matches:
                    raise BackupError(f"Remote path not found: {args.remote_path}")
                target = download(args.remote_path, bool(matches[0]["IsDir"]), Path(args.local_directory), env)
                print(f"Downloaded and decrypted: {target}")
                if args.extract:
                    unpacked = unpack_download(target)
                    print("Unpacked: " + ", ".join(map(str, unpacked)) if unpacked else "No supported archives found.")
            else:
                default = Path(os.environ.get("BACKUP_RESTORE_DIR", Path.cwd() / "restored-backups"))
                interactive(default, env)
        return 0
    except (BackupError, json.JSONDecodeError, OSError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\nCancelled.")
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
