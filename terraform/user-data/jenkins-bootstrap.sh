#!/bin/bash
# Runs as root via cloud-init on first boot of the Jenkins EC2.
# Logs go to /var/log/cloud-init-output.log
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get upgrade -y

# --- Java 21 (current Jenkins LTS requires Java 17 or 21; 21 is the safe choice) ---
apt-get install -y openjdk-21-jdk fontconfig ca-certificates curl gnupg

# Make sure /usr/bin/java points at 21 (Jenkins reads this).
update-alternatives --set java /usr/lib/jvm/java-21-openjdk-amd64/bin/java

# --- Jenkins apt repo ---
# Fetch the current signing key directly from the Ubuntu keyserver over HTTPS
# (avoids needing dirmngr, and avoids the stale jenkins.io-2023.key file).
JENKINS_KEY_FP="0x7198F4B714ABFC68"
rm -f /usr/share/keyrings/jenkins-keyring.gpg /usr/share/keyrings/jenkins-keyring.asc
curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=${JENKINS_KEY_FP}" \
  | gpg --dearmor -o /usr/share/keyrings/jenkins-keyring.gpg
chmod a+r /usr/share/keyrings/jenkins-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.gpg] https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list

apt-get update -y
apt-get install -y jenkins

systemctl daemon-reload
systemctl enable --now jenkins

# --- Docker (so Jenkins can build images on the same host) ---
# Docker's apt repo doesn't publish for every Ubuntu codename on day one.
# Try the host's actual codename first; fall back to noble (24.04 LTS) if missing.
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

DOCKER_CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
if ! curl -fsSL --head "https://download.docker.com/linux/ubuntu/dists/${DOCKER_CODENAME}/Release" >/dev/null; then
    echo "Docker repo has no '${DOCKER_CODENAME}' suite — falling back to 'noble'."
    DOCKER_CODENAME="noble"
fi

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${DOCKER_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Let the jenkins user run docker without sudo (the package created the user).
usermod -aG docker jenkins
systemctl restart jenkins

# --- kubectl (so Jenkins can deploy to the cluster) ---
KUBECTL_VER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/amd64/kubectl" \
  -o /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl

# --- Maven + git (for command-line builds and SCM checkout) ---
apt-get install -y maven git

# --- Pre-create .kube for the jenkins user; kubeconfig is copied in later ---
mkdir -p /var/lib/jenkins/.kube
chown -R jenkins:jenkins /var/lib/jenkins/.kube

echo "Jenkins bootstrap complete. UI on :8080. Initial password at /var/lib/jenkins/secrets/initialAdminPassword"
