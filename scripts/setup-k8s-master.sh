#!/bin/bash
# Run on the K8s master EC2 (as the ubuntu user, with sudo) after user-data finishes.
# Initializes the control plane, sets up kubeconfig, installs Calico CNI,
# and prints the kubeadm join command for the worker.
set -euxo pipefail

# Pod CIDR must match Calico's default (192.168.0.0/16)
sudo kubeadm init --pod-network-cidr=192.168.0.0/16

# Configure kubectl for the ubuntu user
mkdir -p "$HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

# Install Calico (pod network)
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

echo
echo "============================================================"
echo "Waiting for the master node to become Ready..."
echo "============================================================"
for i in {1..30}; do
  if kubectl get nodes 2>/dev/null | grep -q ' Ready'; then
    echo "Master is Ready."
    break
  fi
  sleep 10
done

# Install local-path-provisioner so StatefulSets (Postgres) can claim PVCs.
# kubeadm clusters ship with no default StorageClass; this is the simplest fix.
echo
echo "============================================================"
echo "Installing local-path-provisioner as the default StorageClass"
echo "============================================================"
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
kubectl patch storageclass local-path \
    -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' \
    || true

kubectl get nodes -o wide
kubectl get storageclass

echo
echo "============================================================"
echo "Run the following on the WORKER node (with sudo):"
echo "============================================================"
sudo kubeadm token create --print-join-command
