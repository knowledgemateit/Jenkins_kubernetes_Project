#!/bin/bash
# Run this ONCE on a freshly-launched Ubuntu 22.04 EC2 (t3.micro is enough)
# to turn it into your "deploy server" — the box from which you run Terraform
# and SSH to the Jenkins/K8s nodes.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<you>/<repo>/main/scripts/setup-deploy-server.sh | bash
# OR after cloning:
#   bash scripts/setup-deploy-server.sh
#
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y
sudo apt-get install -y curl unzip git jq gnupg software-properties-common lsb-release

# --- Terraform (HashiCorp apt repo) ---
if ! command -v terraform >/dev/null 2>&1; then
    wget -O- https://apt.releases.hashicorp.com/gpg \
        | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
        | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt-get update -y
    sudo apt-get install -y terraform
fi

# --- AWS CLI v2 ---
if ! command -v aws >/dev/null 2>&1; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    (cd /tmp && unzip -q awscliv2.zip && sudo ./aws/install)
    rm -rf /tmp/aws /tmp/awscliv2.zip
fi

# --- kubectl (so you can run cluster checks from this box too) ---
if ! command -v kubectl >/dev/null 2>&1; then
    curl -fsSL "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
        -o /tmp/kubectl
    sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
    rm /tmp/kubectl
fi

# --- Generate the SSH key Terraform will install on Jenkins/K8s EC2s ---
if [ ! -f "$HOME/.ssh/jenkins_k8s_key" ]; then
    ssh-keygen -t rsa -b 4096 -N "" -f "$HOME/.ssh/jenkins_k8s_key"
fi

echo
echo "================================================================="
echo "Deploy server is ready."
echo
echo "Tools installed:"
terraform version | head -n1
aws --version
kubectl version --client --output=yaml 2>/dev/null | head -n2 || true
git --version
echo
echo "SSH key generated at:"
echo "  ~/.ssh/jenkins_k8s_key       (private — keep secret)"
echo "  ~/.ssh/jenkins_k8s_key.pub   (public  — Terraform installs this on the new EC2s)"
echo
echo "Next: verify AWS auth works, then clone the project and run terraform."
echo "  aws sts get-caller-identity"
echo "================================================================="
