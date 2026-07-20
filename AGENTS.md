# Repository Instructions

These instructions apply to the whole repository.

## Collaboration Rules

- Do not add `Co-authored-by` lines to commits.
- Keep commits atomic: one commit should contain one logical change.
- Do not apply changes to the Kubernetes cluster unless the user explicitly asks for it.
- Do not start implementation work unless the user explicitly asks to begin. When the user is discussing or asking for options, explain and plan first.
- Break large tasks into small, understandable steps and keep the user updated as each step is completed.
- Keep code quality high: prefer simple, readable, maintainable changes over clever shortcuts.
- Follow best practices for the relevant tool, platform, and repository conventions.

## GitOps Notes

- Treat Git as the source of truth for cluster state.
- Prefer declarative changes under `helm/` and `talos/`.
- Secrets under `helm/secrets/*.sops.yaml` must stay encrypted with SOPS.
- Generated Talos manifests and local secrets must not be committed unless they are intentionally encrypted and meant for GitOps.
- For public Cloudflare access, use Authentik ForwardAuth by default only for services that do not provide their own authentication or OIDC. Keep those services reachable without extra authentication from the internal network.
- Do not add the Cloudflare public ForwardAuth layer to services that already have their own OIDC/SSO integration, unless the user explicitly asks for defense-in-depth.
