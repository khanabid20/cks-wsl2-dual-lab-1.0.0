#!/usr/bin/env bash
set -Eeuo pipefail
PROFILE=cks-fast
K8S=v1.35.0
minikube_start(){
  docker info >/dev/null 2>&1 || die "Docker is not usable."
  if minikube status -p "$PROFILE" -o json 2>/dev/null | jq -e '.Host=="Running"' >/dev/null; then
    kubectl config use-context "$PROFILE" >/dev/null
    kubectl get nodes
    return
  fi
  minikube start -p "$PROFILE" --driver=docker --container-runtime=containerd \
    --kubernetes-version="$K8S" --cpus=4 --memory=6144 --disk-size=30g
  kubectl config use-context "$PROFILE" >/dev/null
  kubectl wait --for=condition=Ready node --all --timeout=180s
  kubectl get nodes
  kubectl get pods -A
}
minikube_stop(){ minikube stop -p "$PROFILE" || true; }
minikube_reset(){ minikube delete -p "$PROFILE" >/dev/null 2>&1 || true; echo "Fast Minikube lab deleted."; }
minikube_status(){
  echo "=== Fast lab ==="
  minikube status -p "$PROFILE" || true
  kubectl config use-context "$PROFILE" >/dev/null 2>&1 || true
  kubectl get nodes 2>/dev/null || true
  kubectl get pods -A 2>/dev/null || true
}
