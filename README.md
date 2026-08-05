# Geron

Geron is the GitOps repository for the `vasary` single-node Kubernetes cluster.
It contains the Talos machine configuration, Argo CD bootstrap manifests, and
application manifests for the services running on the node.

## Repository Layout

- `talos/` contains Talos Linux configuration helpers for the bare-metal node.
- `helm/bootstrap/` installs and configures Argo CD.
- `helm/cluster/` is the root Argo CD application entry point.
- `helm/apps/` contains Argo CD `Application` objects and per-app manifests.
- `helm/projects/` defines Argo CD projects.
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
- LibreChat for the LLM and MCP workspace, with Authentik OIDC login.
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
- LibreChat: https://chat.vasary.org
- MCP memory service: `http://mcp-memory-service.mcp.svc.cluster.vasary.org:8765/mcp`
- MCP Paperless: `http://mcp-paperless.mcp.svc.cluster.vasary.org:3101/mcp`
- MCP MikroTik: `http://mcp-mikrotik.mcp.svc.cluster.vasary.org:3105/mcp`
- MCP Pi-hole: `http://mcp-pihole.mcp.svc.cluster.vasary.org:3100/sse`

LibreChat connects the MCP endpoints declaratively from `librechat.yaml`.

## External Dependencies

This cluster depends on a few services outside Kubernetes:

- NAS/NFS server `10.10.10.4`
  - Legacy PVC storage (`nfs`): `/mnt/blaze/k8s/pvc`
  - General PVC storage (`archive-nfs`): `/mnt/archive/kubernetes`
  - NVMe local PVC storage (`local-path-nvme`): `/var/mnt/local-path-nvme`
- SFTP backup server `10.10.0.4:2022`
  - Kubernetes backup jobs authenticate with `sftp-backup-credentials`.
- Local DNS/Pi-hole at `10.10.0.2`
  - Used by Talos DNS/NTP settings and external-dns.
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
the SFTP backup server.

- Authentik PostgreSQL
- Immich PostgreSQL
- LLM Proxy PostgreSQL
- Outline PostgreSQL
- Paperless PostgreSQL and document export
- Seasonvar PostgreSQL
- Seafile MariaDB
- Vaultwarden SQLite and data archive

The reusable uploader lives in
`helm/apps/components/sftp-backup-uploader`. Backup CronJobs opt in with the
`geron.io/sftp-backup: "true"` label and must provide a `backup-work` volume.

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
- After changing manifests under `helm/apps`, commit and push so Argo CD can
  reconcile from Git.
- Services that already have OIDC/SSO should not also receive Cloudflare public
  ForwardAuth unless explicitly desired.
- MariaDB Operator must use `clusterName: cluster.vasary.org`; the cluster does
  not use the default `cluster.local` DNS domain.
