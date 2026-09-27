# Grafana dashboards

Place dashboard JSON files directly in `dashboards/`, commit and push to `master`.
Argo CD discovers this chart through the root application and automatically syncs
one ConfigMap per JSON file into `monitoring`. Grafana's existing dashboard
sidecar provisions ConfigMaps labelled `grafana_dashboard: "1"`.
No file lists, chart version bumps, manual imports or Grafana restarts are needed.

## Add or update a dashboard

1. Export Classic dashboard JSON from Grafana without external sharing.
   Use the dashboard object, not an API request or resource wrapper.
2. Save it as `dashboards/<unique-name>.json`. Set `id: null` and keep a stable,
   unique `uid` and a `title`.
3. Use `prometheus` as the UID of the built-in Prometheus datasource.
   Replace interactive import placeholders such as `${DS_PROMETHEUS}` with real
   UIDs and remove `__inputs`. Dashboard variables and PromQL legends are preserved.
4. Validate locally, then commit and push:

   ```sh
   helm lint helm/workloads/grafana-dashboards
   helm template grafana-dashboards helm/workloads/grafana-dashboards --namespace monitoring
   make -C helm validate
   ```

Use Kubernetes Helm 3 or newer (`nix shell nixpkgs#kubernetes-helm` on NixOS).
Invalid JSON, missing titles/UIDs, duplicate UIDs and interactive import inputs
fail rendering. Each file becomes a separate ConfigMap; keep it comfortably below
the 1 MiB ConfigMap limit and the chart within Helm packaging limits.
JSON is never evaluated as a Helm template.

## Ownership and deletion

Git is the source of truth. Provisioned dashboards cannot be saved from the UI;
export edits and update the JSON in Git. Removing a file removes its ConfigMap
through Argo CD pruning, and Grafana removes the provisioned dashboard.

The hardware dashboard keeps UID `homelab-hardware-talos`, so provisioning updates
the manually imported dashboard if it has that UID. An import with a different UID
remains a separate dashboard.


## Loading behavior

The dashboard collector runs as a native init sidecar and completes its initial
file sync before Grafana starts. It then continues watching ConfigMaps. Grafana
polls dashboard files every 30 seconds; dashboard reload API calls are disabled
so this workflow does not depend on the local admin password.

## Thermal throttle duration

The node-exporter thermal-duration sidecar reads Linux
package_throttle_total_time_ms from read-only host sysfs every 15 seconds.
It exports node_cpu_package_throttle_seconds_total through the textfile collector
using an atomic file replacement on a shared in-memory volume. Each physical
package is read once, rather than summing duplicate per-CPU counters.
Failed or unsupported reads remove the metric file instead of reporting zero.
Throttle Time shows the counter increase over 15 minutes; allow two Prometheus
scrapes after rollout before expecting a value. The collector runs without root
or additional capabilities and does not change CPU settings.
