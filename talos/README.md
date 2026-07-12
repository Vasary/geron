# Geron Talos Single Node

Configuration helpers for a single-node Talos Kubernetes cluster.

## Layout

- `cluster.ini` stores the editable node and cluster settings.
- `patches/controlplane/*.yaml` stores Talos machine config patches: disk wipe/install, network, and single-node scheduling.
- `playbooks/` contains the commands used by `make`.
- `secrets/` is created locally and ignored by git. It contains Talos secrets, generated machine configs, and kubeconfig.

## Default Node

- Control plane IP: `10.10.0.251`
- NAS/storage network IP: `10.10.10.200`
- Install disk: `/dev/nvme0n1`
- Internet/default gateway network: `10.10.0.0/24`

Check interface names in `cluster.ini` before applying the config. The defaults are `eth0` for the main network and `eth1` for the NAS network.

## Workflow

```bash
make check
make secrets
make config
make validate
make disks
make apply
make bootstrap
make health
make dashboard
```

## Patches

- `patches/controlplane/10-install.yaml` sets `/dev/nvme0n1` and `wipe: true`.
- `patches/controlplane/20-network.yaml` sets `eth0` on `10.10.0.251/24`, default gateway `10.10.0.1`, DNS `10.10.0.2`, and the optical/NAS interface `eth1` on `10.10.10.200/24`.
- `patches/controlplane/25-time.yaml` sets NTP to `10.10.0.2`.
- `patches/controlplane/30-single-node.yaml` allows workloads on the control plane and sets `cluster.local`.

`make secrets` creates `secrets/talos-secrets.yaml`.

`make config` generates `secrets/generated/controlplane.yaml` and `secrets/generated/talosconfig` from `patches/controlplane/*.yaml`.

`make apply` uses the Talos maintenance API and applies `secrets/generated/controlplane.yaml`. That config installs Talos to the NVMe disk declared in `patches/controlplane/10-install.yaml` with `wipe: true`.

`make disks` is intended before installation and uses the insecure Talos maintenance API. After Talos is installed and the generated `talosconfig` works, use `make disks-auth`.

`make dashboard` opens an authenticated interactive terminal UI and works after Talos is installed/configured. In maintenance mode use `make disks`, `make status`, and `make apply`; the dashboard command does not support the insecure maintenance API.

After the node installs and reboots, run `make bootstrap`. The kubeconfig will be written to `secrets/kubeconfig`.

Use it like this:

```bash
KUBECONFIG=$PWD/secrets/kubeconfig kubectl get nodes
```
