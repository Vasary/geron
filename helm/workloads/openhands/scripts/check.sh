#!/usr/bin/env sh
set -eu

namespace="${1:-openhands}"
host="${2:-https://openhands.vasary.org/}"

kubectl -n "$namespace" get pods,svc,ingress,pvc
kubectl -n "$namespace" rollout status statefulset/openhands --timeout=10m
kubectl -n "$namespace" get statefulset openhands -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
kubectl -n "$namespace" get statefulset openhands -o jsonpath='{.spec.template.spec.volumes}{"\n"}'
curl -I "$host"
