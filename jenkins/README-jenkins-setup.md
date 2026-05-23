# Jenkins post-install setup

Reference notes for the Jenkins-specific portions of the main [README.md](../README.md). The high-level walkthrough (Steps 1–11) lives there. This page goes deeper on plugins, credentials, and kubeconfig — the parts most likely to bite.

## 1. Unlock Jenkins

Open `http://<jenkins_public_ip>:8080`. Jenkins asks for the initial admin password. From the **deploy EC2**, SSH into the Jenkins box and read it:

```bash
ssh -i ~/.ssh/project ubuntu@<jenkins_public_ip>
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

## 2. Install plugins

Pick **"Install suggested plugins"**, then add the extras from [plugins.txt](plugins.txt):

- Manage Jenkins → Plugins → Available
- Search and install: `Docker Pipeline`, `Kubernetes CLI`, `Pipeline Utility Steps`, `Credentials Binding`

## 3. Add credentials

Manage Jenkins → Credentials → System → Global credentials → Add Credentials:

| ID | Kind | Description |
|---|---|---|
| `dockerhub-creds` | Username with password | Your Docker Hub login. Used by the pipeline to push the image. |
| `github-creds` *(optional)* | Username with password / token | Only needed if your GitHub repo is private. |

The `dockerhub-creds` ID is referenced by name in [Jenkinsfile](Jenkinsfile) — it must match exactly.

## 4. Verify the jenkins user can run docker

The user-data script adds `jenkins` to the `docker` group, but a Jenkins service restart is required for the group membership to take effect:

```bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
sudo -u jenkins docker ps      # should NOT print a permission error
```

## 5. Wire kubeconfig so Jenkins can deploy

After you've run `setup-k8s-master.sh` on the master and the worker has joined, copy the kubeconfig to the Jenkins server. **All commands run on the deploy EC2 and the EC2s themselves — nothing on your laptop.**

```bash
# 5a. From the deploy EC2 — make the SSH private key available on the master
#     (so master can scp the kubeconfig to Jenkins).
scp -i ~/.ssh/project ~/.ssh/project \
    ubuntu@<k8s_master_public_ip>:~/.ssh/

# 5b. SSH from the deploy EC2 into the master
ssh -i ~/.ssh/project ubuntu@<k8s_master_public_ip>

# 5c. (on master) Copy kubeconfig to the Jenkins server's ubuntu user
chmod 600 ~/.ssh/project
scp -i ~/.ssh/project -o StrictHostKeyChecking=no \
    ~/.kube/config ubuntu@<jenkins_private_ip>:/tmp/kubeconfig

# 5d. (still on master) Hop to Jenkins to install it for the jenkins user
ssh -i ~/.ssh/project ubuntu@<jenkins_private_ip>
sudo mkdir -p /var/lib/jenkins/.kube
sudo mv /tmp/kubeconfig /var/lib/jenkins/.kube/config
sudo chown -R jenkins:jenkins /var/lib/jenkins/.kube

# 5e. Verify the server: address. kubeadm normally writes the master's
#     PRIVATE IP — confirm it's not 127.0.0.1 or a hostname Jenkins can't resolve.
sudo grep '^    server:' /var/lib/jenkins/.kube/config
# Expected:  server: https://<master-private-ip>:6443

# If wrong, fix it:
sudo sed -i 's|server: https://.*:6443|server: https://<k8s_master_private_ip>:6443|' \
    /var/lib/jenkins/.kube/config

# 5f. Smoke test
sudo -u jenkins kubectl get nodes      # should list both nodes
```

## 6. Create the pipeline job

- Dashboard → New Item
- Name: `demo-app-cicd`, Type: **Pipeline**, OK
- Under **Pipeline**:
  - Definition: **Pipeline script from SCM**
  - SCM: Git
  - Repository URL: `https://github.com/<you>/my-jenkins-k8s-project.git`
  - Branch: `*/main`
  - Script Path: `jenkins/Jenkinsfile`
- Under **General → This project is parameterized** (recommended): add a String parameter `DOCKERHUB_USER` with your Docker Hub username. Otherwise edit the default in [Jenkinsfile](Jenkinsfile).
- Save → **Build Now**

## 7. Common issues

| Symptom | Cause / fix |
|---|---|
| `docker: permission denied` | `jenkins` not in docker group, or you forgot `systemctl restart jenkins` after `usermod -aG`. |
| `kubectl: connection refused` | kubeconfig `server:` is `127.0.0.1` or the master's public IP — change to the master's **private** IP. |
| `Unable to connect to the server: dial tcp ... i/o timeout` | Security group blocking 6443. Confirm `aws_security_group_rule.k8s_from_jenkins` exists in [security-groups.tf](../terraform/security-groups.tf). |
| Pods stuck in `ImagePullBackOff` | Docker Hub repo private and K8s nodes have no creds. Make the repo public, or add an `imagePullSecret`. |
| `Could not find credentials entry with ID 'dockerhub-creds'` | Credentials ID typo — must be exactly `dockerhub-creds` (Step 3). |
| Pipeline checkout fails on a private GitHub repo | Add `github-creds` and reference it in the job's SCM section. |
