#!/bin/bash
# Run on the K8s master (or anywhere with kubeconfig) to sanity-check the cluster.
set -euo pipefail

echo "=== Nodes ==="
kubectl get nodes -o wide

echo
echo "=== System pods (kube-system) ==="
kubectl get pods -n kube-system

echo
echo "=== Cluster info ==="
kubectl cluster-info

echo
echo "=== Demo app namespace (only if deployed) ==="
kubectl get all -n demo-app 2>/dev/null || echo "demo-app namespace not yet created"
