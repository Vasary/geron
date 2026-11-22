# Geron

[![Renovate](https://github.com/Vasary/geron/actions/workflows/renovate.yaml/badge.svg)](https://github.com/Vasary/geron/actions/workflows/renovate.yaml)

Geron is the GitOps repository for the `vasary` single-node Kubernetes cluster.
It contains the Talos machine configuration, Argo CD bootstrap manifests, and
application manifests for the services running on the node.

## Repository Layout

- `talos/` contains Talos Linux configuration helpers for the bare-metal node.
- `helm/bootstrap/` installs and configures Argo CD.
- `helm/cluster/` is the root Argo CD application entry point.
- `helm/argocd/` contains Argo CD projects and `Application` objects.
- `helm/platform/` contains namespaces, shared components, and cluster-level config.
- `helm/workloads/` contains local per-service Kubernetes manifests.
- `helm/secrets/*.sops.yaml` stores encrypted Kubernetes secrets.

Git is the source of truth for the cluster. Prefer changing manifests here and
letting Argo CD reconcile them.

## Cluster

The cluster is a single-node Talos Kubernetes installation.

- Cluster name: `vasary`
- Kubernetes endpoint: `10.10.0.251:6443`
- Main ingress/load balancer IP: `10.10.0.250`
- Kubernetes DNS domain: `cluster.vasary.org`
- Main public/internal domain: `vasary.org`

The Talos node also has a storage/NAS network interface. See
`talos/README.md` for the lower-level install workflow and node details.

## Installed Components

Core platform:

- Argo CD for GitOps reconciliation.
- Traefik as the ingress controller.
- MetalLB for the local load balancer IP.
- cert-manager with Let's Encrypt DNS-01 certificates.
- external-dns for local DNS automation.
- NFS CSI for NAS-backed persistent volumes.
- local-path-provisioner for node-local storage.
- local-path-provisioner-nvme for node-local storage on the Talos
  `local-path-nvme` user volume.
- CloudNativePG for PostgreSQL databases.
- MariaDB Operator for MariaDB databases.
- Redis Operator, metrics-server, reloader, and kube-prometheus-stack.

Applications:

- Authentik for SSO and OAuth/OIDC integration.
- Grafana and Prometheus for monitoring.
- Immich.
- Jellyfin and Seasonvar.
- Outline.
- Seafile.
- Stirling PDF.
- Echo server for testing ingress/auth routing.
- Cloudflared tunnel deployment.

AI platform:

- Argo CD project: `ai-platform`
- MCP Paperless: `http://mcp-paperless.mcp.svc.cluster.vasary.org:3101/mcp`
- MCP MikroTik: `http://mcp-mikrotik.mcp.svc.cluster.vasary.org:3105/mcp`
- MCP AdGuard Home: `http://mcp-adguard.mcp.svc.cluster.vasary.org:3100/mcp`

The AdGuard MCP uses `@fcannizzaro/mcp-adguard-home@1.0.6` through
`supercorp/supergateway:4.2.0` on an internal ClusterIP Service, without Ingress.
An init container installs the pinned MCP package into an ephemeral volume;
starting a new pod requires access to the npm registry.
Credentials and the gateway API key are stored in `helm/secrets/mcp-adguard.sops.yaml`
in the `mcp` namespace. Apply encrypted secrets with `make -C helm deploy-secrets`
before syncing the application.
ExternalDNS owns the Ingress DNS rewrite rules; preserve these and other existing
rules when changing AdGuard filtering rules through MCP.

## External Dependencies

This cluster depends on a few services outside Kubernetes:

- NAS/NFS server `10.10.10.4`
  - Legacy PVC storage (`nfs`): `/mnt/blaze/k8s/pvc`
  - General PVC storage (`archive-nfs`): `/mnt/archive/kubernetes`
  - NVMe local PVC storage (`local-path-nvme`): `/var/mnt/local-path-nvme`
- SFTP backup server `10.10.0.4:2022`
  - Kubernetes backup jobs authenticate with `sftp-backup-credentials`.
- AdGuard Home at `192.168.178.3`
  - ExternalDNS manages internal DNS records through the AdGuard webhook provider.
- Default gateway on `10.10.0.1`.
- Cloudflare
  - DNS-01 ACME challenges for certificates.
  - Cloudflare tunnel token for `cloudflared`.
- GitHub
  - Argo CD reads this repository.
- SOPS age key at `~/.config/sops/age/keys.txt`
  - Required to decrypt and apply secrets.

## Backups

Backups are plain Kubernetes `CronJob` resources. Jobs write dump/export data to
an `emptyDir` work directory and a shared `rclone` sidecar uploads the result to
the configured remote storage.

- Authentik PostgreSQL
- Immich PostgreSQL
- LLM Proxy PostgreSQL
- Outline PostgreSQL
- Paperless PostgreSQL and document export
- Seasonvar PostgreSQL
- Seafile MariaDB
- Vaultwarden SQLite and data archive

The reusable uploader lives in
`helm/platform/components/sftp-backup-uploader`. Backup CronJobs opt in with the
`geron.io/sftp-backup: "true"` label and must provide a `backup-work` volume.
After a successful upload, the uploader keeps the two newest timestamped backup
copies in each backup series. Override the limit on a CronJob's Pod template:

```yaml
spec:
  jobTemplate:
    spec:
      template:
        metadata:
          annotations:
            geron.io/backup-retention: "7"
```

The retention value must be a positive integer. Missing or invalid values use
the default of `2`.

The Pod template annotation `geron.io/backup-destination` selects exactly one
storage backend:

- `sftp` (the default) uploads the backup without an additional encryption
  layer to the existing SFTP server.
- `google-drive` uploads through an rclone `crypt` remote. File contents, file
  names, and directory names are encrypted locally before they leave the Pod.

For Google Drive, `geron.io/google-drive-path` optionally selects the directory
used for encrypted objects and defaults to `geron-backups`:

```yaml
spec:
  jobTemplate:
    spec:
      template:
        metadata:
          annotations:
            geron.io/backup-destination: google-drive
            geron.io/google-drive-path: geron-backups
            geron.io/backup-retention: "7"
```

Google Drive mode reads `GOOGLE_DRIVE_CLIENT_ID`,
`GOOGLE_DRIVE_CLIENT_SECRET`, `GOOGLE_DRIVE_TOKEN`,
`BACKUP_CRYPT_PASSWORD`, and `BACKUP_CRYPT_SALT` from the existing
`sftp-backup-credentials` Secret. These values must remain SOPS-encrypted. The
OAuth token should use the `drive.file` scope so the backup client can access
only files it created. Keep both crypt secrets in a separate password manager:
losing either one makes the encrypted backups unrecoverable.

Google Drive shows encrypted object names by design. List backups with their
decrypted paths through the helper script:

```bash
make helm backups
nix shell nixpkgs#rclone -c helm/scripts/google-drive-backups.sh list
nix shell nixpkgs#rclone -c helm/scripts/google-drive-backups.sh list outline
```

With no arguments, the helper starts an interactive browser, loads credentials
from SOPS into its process environment, verifies the required fields and tests
the Google Drive connection before showing any backups. The browser shows
directories first, followed by files with their decrypted names, sizes, and
modification times. Enter an item number to open a directory or download a
file; use `d` to download the current directory and `u` to go up. After an
interactive download, the helper can also unpack `tar`, `zip`, `gz`, `bz2`, and
`xz` archives. Set `BACKUP_RESTORE_DIR` to change the default local destination.

Download and decrypt one backup locally:

```bash
nix shell nixpkgs#rclone -c \
  helm/scripts/google-drive-backups.sh download \
  outline/outline-20261120T190726Z.sql.gz ./restored-backups
```

Add `--extract` to download, decrypt, and unpack in one non-interactive command:

```bash
nix shell nixpkgs#rclone -c \
  helm/scripts/google-drive-backups.sh download \
  outline/outline-20261120T190726Z.sql.gz ./restored-backups --extract
```

Downloaded archives are kept alongside the unpacked data. Archive extraction
rejects entries that would write outside the destination directory.

The SFTP directory layout follows the application name, for example
`paperless/postgres`, `paperless/export-<timestamp>`, `vaultwarden`, and
`seafile`.

## Common Commands

Top-level wrappers:

```bash
make talos check
make talos config
make talos apply-try
make talos health

make helm validate
make helm deploy
make helm deploy-secrets
```

Talos:

- `make talos check` verifies local tools and parses `talos/cluster.ini`.
- `make talos secrets` generates local Talos secrets.
- `make talos config` renders Talos machine config.
- `make talos validate` validates the rendered config.
- `make talos apply` applies config in maintenance mode.
- `make talos apply-try` applies config through the authenticated Talos API in try mode.
- `make talos apply-no-reboot` applies config through the authenticated Talos API without rebooting.
- `make talos bootstrap` bootstraps the Kubernetes control plane.
- `make talos kubeconfig` writes Kubernetes access config.
- `make talos health` checks Talos/Kubernetes health.
- `make talos reboot` drains and reboots the Talos node.
- `make talos shutdown` drains and powers off the Talos node.

Helm/Argo CD:

- `make helm validate` checks that `helm/cluster` renders.
- `make helm deploy` installs Argo CD and the root application.
- `make helm deploy-secrets` decrypts and applies all SOPS secrets.
- `make helm argocd-password` generates the encrypted Argo CD admin secret.
- `make helm authentik-bootstrap-password` updates the encrypted Authentik
  bootstrap password.
- `make helm authentik-password` resets the live Authentik admin password and
  updates the encrypted secret.

Useful kubectl checks:

```bash
kubectl -n argocd get applications
kubectl get nodes -o wide
kubectl get ingress -A
kubectl get certificates -A
kubectl get pvc -A
kubectl get cronjob -A
```

## Secrets

Secrets under `helm/secrets/*.sops.yaml` must remain encrypted with SOPS. Do not
commit decrypted secret files or generated Talos secrets. Local Talos material is
generated under `talos/secrets/` or `talos/manifests/` and is intentionally not
part of the GitOps state unless explicitly encrypted and committed.

## Operational Notes

- Do not apply Kubernetes cluster changes manually unless there is a reason to
  bypass GitOps temporarily.
- After changing manifests under `helm/argocd`, `helm/platform`, or `helm/workloads`, commit and push so Argo CD can
  reconcile from Git.
- Services that already have OIDC/SSO should not also receive Cloudflare public
  ForwardAuth unless explicitly desired.
- MariaDB Operator must use `clusterName: cluster.vasary.org`; the cluster does
  not use the default `cluster.local` DNS domain.

### Best-effort backup uploads

SFTP upload failures are logged as warnings and complete the backup Job successfully,
including when the NAS is offline. A successful Job therefore does not guarantee a
remote backup: check the `sftp-upload` logs for `Backup uploaded successfully`.
Unsent files live in `emptyDir` and are lost when the pod is removed; a later run
creates a new backup rather than retrying the previous one. Failures reported by
the backup producer still fail the Job.

Existing Jobs retain their original commands; the upload policy affects new Jobs.
Previously failed Jobs may keep Argo CD degraded until CronJob history cleanup.

## Grafana dashboards

Add JSON files to [the dashboards directory](helm/workloads/grafana-dashboards/dashboards/)
and Argo CD will provision them in Grafana. See the
[dashboard workflow](helm/workloads/grafana-dashboards/README.md).
