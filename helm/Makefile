SHELL := bash

ARGOCD_NAMESPACE ?= argocd
GIT_ORIGIN ?= $(shell git config --get remote.origin.url)
ARGOCD_REPO_URL ?= $(shell printf '%s\n' '$(GIT_ORIGIN)' | sed -E 's#^git@github.com:(.*)\.git$$#https://github.com/\1.git#')
ARGOCD_REVISION ?= $(shell git rev-parse --abbrev-ref HEAD)
ARGOCD_ROOT_PATH ?= helm/cluster
ARGOCD_WAIT_TIMEOUT ?= 300s
SOPS_AGE_KEY_FILE ?= $(HOME)/.config/sops/age/keys.txt

.DEFAULT_GOAL := help

.PHONY: help validate deploy deploy-secrets argocd-password github-runner-token hermes-secrets

help:
	@printf '%s\n' \
		'Targets:' \
		'  make validate        Validate Argo CD platform manifests' \
		'  make deploy          Install Argo CD and bootstrap from git origin' \
		'  make deploy-secrets  Decrypt and apply SOPS Kubernetes secrets' \
		'  make argocd-password Generate encrypted Argo CD admin password secret' \
		'  make github-runner-token Generate encrypted GitHub runner token secret' \
		'  make hermes-secrets Generate encrypted Hermes Telegram secret' \
		'' \
		'Variables:' \
		'  GIT_ORIGIN=$(GIT_ORIGIN)' \
		'  ARGOCD_REPO_URL=$(ARGOCD_REPO_URL)' \
		'  ARGOCD_REVISION=$(ARGOCD_REVISION)' \
		'  ARGOCD_ROOT_PATH=$(ARGOCD_ROOT_PATH)' \
		'  ARGOCD_WAIT_TIMEOUT=$(ARGOCD_WAIT_TIMEOUT)' \
		'  SOPS_AGE_KEY_FILE=$(SOPS_AGE_KEY_FILE)'

validate:
	@command -v kubectl >/dev/null
	@test -n "$(ARGOCD_REPO_URL)" || { printf '%s\n' 'Missing git remote origin. Set it with: git remote add origin <url>'; exit 1; }
	@kubectl kustomize cluster >/dev/null
	@printf '%s\n' 'helm/cluster renders successfully.'

deploy: validate
	@printf '%s\n' 'Installing Argo CD bootstrap manifests...'
	@kubectl apply --server-side --force-conflicts -k bootstrap/argocd
	@printf '%s\n' 'Waiting for Argo CD to become ready...'
	@kubectl -n "$(ARGOCD_NAMESPACE)" rollout status deploy/argocd-redis --timeout="$(ARGOCD_WAIT_TIMEOUT)"
	@kubectl -n "$(ARGOCD_NAMESPACE)" rollout status deploy/argocd-repo-server --timeout="$(ARGOCD_WAIT_TIMEOUT)"
	@kubectl -n "$(ARGOCD_NAMESPACE)" rollout status deploy/argocd-server --timeout="$(ARGOCD_WAIT_TIMEOUT)"
	@kubectl -n "$(ARGOCD_NAMESPACE)" rollout status statefulset/argocd-application-controller --timeout="$(ARGOCD_WAIT_TIMEOUT)"
	@printf 'Bootstrapping root Application from %s (%s:%s)...\n' "$(ARGOCD_REPO_URL)" "$(ARGOCD_REVISION)" "$(ARGOCD_ROOT_PATH)"
	@sed \
		-e 's|__ARGOCD_REPO_URL__|$(ARGOCD_REPO_URL)|g' \
		-e 's|__ARGOCD_REVISION__|$(ARGOCD_REVISION)|g' \
		-e 's|__ARGOCD_ROOT_PATH__|$(ARGOCD_ROOT_PATH)|g' \
		bootstrap/root-application.yaml | kubectl apply -f -
	@printf '%s\n' 'Waiting for root Application to appear...'
	@for i in $$(seq 1 60); do \
		if kubectl -n "$(ARGOCD_NAMESPACE)" get application geron-cluster >/dev/null 2>&1; then \
			break; \
		fi; \
		if [ "$$i" -eq 60 ]; then \
			printf '%s\n' 'Timed out waiting for application/geron-cluster.' >&2; exit 1; \
		fi; \
		sleep 5; \
	done
	@kubectl -n "$(ARGOCD_NAMESPACE)" get applications
	@printf '%s\n' \
		'' \
		'Argo CD is bootstrapped. It will reconcile helm/cluster from git.' \
		'UI: https://vasary.org' \
		'Login: admin' \
		'Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d'

deploy-secrets:
	@command -v sops >/dev/null
	@test -f "$(SOPS_AGE_KEY_FILE)" || { printf 'Missing SOPS age key: %s\n' "$(SOPS_AGE_KEY_FILE)" >&2; exit 1; }
	@kubectl apply -k apps/namespaces
	@set -e; \
	for secret in secrets/*.sops.yaml; do \
		[ -e "$$secret" ] || { printf '%s\n' 'No SOPS secrets found in helm/secrets/*.sops.yaml'; exit 1; }; \
		printf 'Applying %s\n' "$$secret"; \
		SOPS_AGE_KEY_FILE="$(SOPS_AGE_KEY_FILE)" sops -d "$$secret" | kubectl apply -f -; \
	done

argocd-password:
	@SOPS_AGE_KEY_FILE="$(SOPS_AGE_KEY_FILE)" bash scripts/set-argocd-admin-password.sh secrets/argocd-admin-password.sops.yaml

github-runner-token:
	@SOPS_AGE_KEY_FILE="$(SOPS_AGE_KEY_FILE)" bash scripts/set-github-runner-token.sh secrets/github-runner-auth.sops.yaml

hermes-secrets:
	@SOPS_AGE_KEY_FILE="$(SOPS_AGE_KEY_FILE)" bash scripts/set-hermes-secrets.sh secrets/hermes.sops.yaml
