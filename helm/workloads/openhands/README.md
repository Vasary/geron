# OpenHands Agent Canvas

GitOps deployment for OpenHands Agent Canvas.

## Architecture

- Namespace: `openhands`
- Public/internal URL: `https://openhands.vasary.org`
- Ingress: Traefik + cert-manager `letsencrypt-prod`
- Authentication: Authentik ForwardAuth middleware
- SSO access group: `openhands-users`
- Control-plane state: PVC mounted at `/home/openhands/.openhands`
- Runtime workspace: `emptyDir` mounted at `/home/openhands/workspace`
- Workspace limit: `emptyDir.sizeLimit: 20Gi`
- Pod ephemeral storage limit: `24Gi`
- Kubernetes API access: disabled by default (`automountServiceAccountToken: false`, chart RBAC off)
- LLM endpoint: `http://llm-proxy.llm-proxy.svc.cluster.vasary.org/v1`

The chart is vendored from the official OpenHands `helm/agent-canvas` chart
and minimally extended with `extraVolumes`, `extraVolumeMounts`, and local
Vasary values.

## LLM Secret

The LLM API key is stored in the SOPS-encrypted secret:

```text
helm/secrets/openhands.sops.yaml
```

Apply it with the repo's standard secret flow:

```sh
make -C helm deploy-secrets
```

Change the model in:

```text
helm/workloads/openhands/agent-canvas-chart/values-vasary.yaml
```

Default:

```yaml
LLM_MODEL: gpt-4o-mini
```

## Deploy / Update

This repo is the source of truth. To deploy:

```sh
git push origin master
```

ArgoCD will sync:

- `helm/platform/namespaces/openhands.yaml`
- `helm/argocd/applications/ai/openhands.yaml`
- `helm/workloads/openhands/agent-canvas-chart`
- Authentik blueprint changes for the ForwardAuth app

The Authentik blueprint creates:

- group `openhands-users`
- proxy provider `openhands`
- application `OpenHands`
- policy binding allowing members of `openhands-users`

Add your user to `openhands-users` after the blueprint is applied.

## Verification

After Argo sync:

```sh
kubectl -n openhands get pods,svc,ingress,pvc
kubectl -n openhands rollout status statefulset/openhands --timeout=10m
kubectl -n openhands describe pod -l app.kubernetes.io/name=agent-canvas
curl -I https://openhands.vasary.org/
```

Expected properties:

- Ingress has TLS secret `openhands-vasary-tls`.
- Browser access redirects through Authentik.
- The pod has a PVC only for `/home/openhands/.openhands`.
- `/home/openhands/workspace` is an `emptyDir` with `sizeLimit: 20Gi`.
- The pod has `ephemeral-storage` request/limit.
- The service account token is not mounted.

Runtime checks from inside the pod:

```sh
kubectl -n openhands exec statefulset/openhands -- df -h /home/openhands/workspace
kubectl -n openhands exec statefulset/openhands -- sh -lc 'echo ok > /home/openhands/workspace/probe && cat /home/openhands/workspace/probe'
```

State persistence check:

```sh
kubectl -n openhands delete pod openhands-0
kubectl -n openhands rollout status statefulset/openhands --timeout=10m
```

Then confirm prior Agent Canvas history/settings still exist in the UI.

## Limitations

The official Agent Canvas Helm chart is an experimental single-replica
all-in-one deployment. Upstream explicitly states it is single-tenant and does
not provide isolated per-agent containers. This deployment therefore provides:

- A persistent control plane.
- An ephemeral non-persistent workspace for the Agent Canvas pod.
- Authentik protection at ingress.
- No Kubernetes RBAC for agents by default.

It does not yet provide one Kubernetes Job/Pod per individual agent task. That
requires either OpenHands Enterprise isolated sandboxes or a custom
orchestration layer using a stable upstream Agent Server API. Do not treat this
deployment as hard multi-agent filesystem isolation.

## Cleanup

GitOps removal:

```sh
git rm helm/argocd/applications/ai/openhands.yaml
git rm -r helm/workloads/openhands
git rm helm/platform/namespaces/openhands.yaml
git push origin master
```

If you want to delete retained PVC data after Argo prunes the app:

```sh
kubectl -n openhands delete pvc --all
```
