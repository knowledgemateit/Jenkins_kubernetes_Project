#!/bin/bash
# Runs as root via cloud-init on first boot of both the K8s master and worker.
# Installs containerd + kubeadm/kubelet/kubectl and configures kernel params.
# Logs go to /var/log/cloud-init-output.log
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get upgrade -y
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

# --- Disable swap (required by kubelet) ---
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# --- Kernel modules required by container runtime ---
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# --- sysctl required for K8s networking ---
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# --- Install containerd ---
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null
# Use systemd cgroup driver (required by recent kubelet)
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# --- Install kubeadm, kubelet, kubectl (v1.29) ---
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' \
  | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable --now kubelet

# --- Stage post-provision scripts on the instance for convenience ---
# These are also kept in the repo under scripts/. We embed them inline
# so the user can run them right after SSH without re-uploading.
mkdir -p /tmp
cat <<'MASTER_EOF' > /tmp/setup-k8s-master.sh
#!/bin/bash
set -euxo pipefail
# Initialize the control plane. Pod CIDR matches Calico's default.
sudo kubeadm init --pod-network-cidr=192.168.0.0/16

# Set up kubeconfig for the ubuntu user
mkdir -p /home/ubuntu/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
sudo chown ubuntu:ubuntu /home/ubuntu/.kube/config

# Install the Calico CNI plugin
export KUBECONFIG=/home/ubuntu/.kube/config
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

echo
echo "================================================================="
echo "Master is ready. The kubeadm join command for the worker is below:"
echo "================================================================="
sudo kubeadm token create --print-join-command
MASTER_EOF
chmod +x /tmp/setup-k8s-master.sh
chown ubuntu:ubuntu /tmp/setup-k8s-master.sh

echo "K8s common bootstrap complete. Run /tmp/setup-k8s-master.sh on the master, then the printed kubeadm join on the worker."
