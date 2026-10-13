# Vasary Notes

This chart is vendored from the official OpenHands Agent Canvas chart and has
local changes for this cluster:

- `extraVolumes` and `extraVolumeMounts` are supported.
- `values-vasary.yaml` persists only `/home/openhands/.openhands`.
- `/home/openhands/workspace` is mounted from `emptyDir` with `sizeLimit: 20Gi`.
- Auth is handled by Authentik ForwardAuth at Traefik, not by OpenHands itself.

The upstream `README.md` is kept for reference and still describes the default
official chart behavior, including persistent `~/workspace`.
