SHELL := bash

ARGOCD_NAMESPACE ?= argocd
ARGOCD_REPO_URL ?= $(shell git config --get remote.origin.url)
ARGOCD_REVISION ?= $(shell git rev-parse --abbrev-ref HEAD)
ARGOCD_ROOT_PATH ?= helm/cluster
ARGOCD_WAIT_TIMEOUT ?= 300s

.DEFAULT_GOAL := help

.PHONY: help validate deploy deploy-secrets

help:
	@printf '%s\n' \
		'Targets:' \
		'  make validate        Validate Argo CD platform manifests' \
		'  make deploy          Install Argo CD and bootstrap from git origin' \
		'  make deploy-secrets  Apply local ignored Kubernetes secrets' \
		'' \
		'Variables:' \
		'  ARGOCD_REPO_URL=$(ARGOCD_REPO_URL)' \
		'  ARGOCD_REVISION=$(ARGOCD_REVISION)' \
		'  ARGOCD_ROOT_PATH=$(ARGOCD_ROOT_PATH)' \
		'  ARGOCD_WAIT_TIMEOUT=$(ARGOCD_WAIT_TIMEOUT)'

validate:
	@command -v kubectl >/dev/null
	@test -n "$(ARGOCD_REPO_URL)" || { printf '%s\n' 'Missing git remote origin. Set it with: git remote add origin <url>'; exit 1; }
	@kubectl kustomize cluster >/dev/null
	@printf '%s\n' 'helm/cluster renders successfully.'

deploy: validate
	@printf '%s\n' 'Installing Argo CD bootstrap manifests...'
	@kubectl apply -k bootstrap/argocd
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
		'UI: http://geron.cfv3.org' \
		'Login: admin' \
		'Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d'

deploy-secrets:
	@kubectl apply -k secrets
