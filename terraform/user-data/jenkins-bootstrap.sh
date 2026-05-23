#!/bin/bash
# Runs as root via cloud-init on first boot of the Jenkins EC2.
# Logs go to /var/log/cloud-init-output.log
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get upgrade -y

# --- Java 17 (Jenkins LTS requirement) ---
apt-get install -y openjdk-17-jdk

# --- Jenkins ---
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key \
  | tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
https://pkg.jenkins.io/debian-stable binary/" \
  | tee /etc/apt/sources.list.d/jenkins.list > /dev/null
apt-get update -y
apt-get install -y jenkins
systemctl enable jenkins
systemctl start jenkins

# --- Docker (so Jenkins can build images on the same host) ---
apt-get install -y ca-certificates curl gnupg lsb-release
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Allow the jenkins user to use docker.
usermod -aG docker jenkins
systemctl restart jenkins

# --- kubectl (so Jenkins can deploy to the cluster) ---
curl -fsSL "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
  -o /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl

# --- Maven (for command-line builds; Jenkins itself can also install via tools) ---
apt-get install -y maven git

# --- Git ---
apt-get install -y git

# --- Create .kube directory for the jenkins user (kubeconfig will be copied here later) ---
mkdir -p /var/lib/jenkins/.kube
chown -R jenkins:jenkins /var/lib/jenkins/.kube

echo "Jenkins bootstrap complete. UI on :8080. Initial password at /var/lib/jenkins/secrets/initialAdminPassword"
