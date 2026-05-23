# Jenkins + Kubernetes on EC2 — End-to-End Project (EC2-only)

A complete CI/CD pipeline running **entirely on AWS EC2** (Ubuntu 26.04 LTS). You launch one small "deploy" EC2, SSH in, and from there you provision and operate the rest. The workload is a **two-service microservices app** — `user-service` and `product-service`, each backed by its own PostgreSQL StatefulSet — built and deployed by Jenkins.

### Infrastructure (4 EC2s)

- **Deploy EC2** (t3.micro) — runs Terraform, kubectl, ssh. Your control room.
- **Jenkins EC2** (t3.medium) — Jenkins LTS + Docker + kubectl. Builds the images, deploys to K8s.
- **K8s master EC2** (t3.medium) — kubeadm control plane.
- **K8s worker EC2** (t3.medium) — runs the application + database pods.

### Workload (inside the K8s cluster)

```
                                   K8s namespace: demo-app
   +------------------------------------------------------------------+
   |                                                                  |
   |   +-------------------+              +-------------------+       |
   |   |  user-service     |              |  product-service  |       |
   |   |  Deployment x2    |              |  Deployment x2    |       |
   |   |  Spring Boot      |              |  Spring Boot      |       |
   |   |  /users  REST     |              |  /products REST   |       |
   |   +---------+---------+              +---------+---------+       |
   |             | JDBC                             | JDBC            |
   |             v                                  v                 |
   |   +-------------------+              +-------------------+       |
   |   |  user-postgres    |              | product-postgres  |       |
   |   |  StatefulSet      |              |  StatefulSet      |       |
   |   |  PVC: 2Gi         |              |  PVC: 2Gi         |       |
   |   +-------------------+              +-------------------+       |
   |                                                                  |
   +-------+----------------------------------------------+-----------+
           ^                                              ^
           | NodePort 30081                               | NodePort 30082
           |                                              |
        curl http://<worker_ip>:30081/users          /products
```

### Build & deploy flow

```
                       +------------------+
                       |  AWS Console     |
                       +--------+---------+
                                |
                                v
                       +------------------+
                       |   Deploy EC2     |
                       |  terraform/aws   |
                       +--------+---------+
                                | terraform apply
                                v
                +-------------+ + +-------------+ + +-------------+
                |  Jenkins    |   |  k8s-master |   |  k8s-worker |
                |   EC2       |   |     EC2     |   |     EC2     |
                +------+------+   +-------------+   +-------------+
                       | mvn package x2
                       | docker build x2
                       | docker push  x2 ----> [Docker Hub]
                       | kubectl apply k8s/* -> [K8s cluster]
```

---

## Project layout

```
kuberenetes_jenkins_project/
├── README.md                          <- you are here
├── .gitignore
├── terraform/                         <- IaC: 3 Ubuntu EC2s + SG + key pair
│   ├── providers.tf, variables.tf, main.tf
│   ├── security-groups.tf, outputs.tf
│   ├── terraform.tfvars.example
│   └── user-data/
│       ├── jenkins-bootstrap.sh       <- installs Jenkins/Docker/kubectl/Java
│       └── k8s-common-bootstrap.sh    <- installs containerd/kubeadm/kubelet
├── scripts/
│   ├── setup-deploy-server.sh         <- run on the deploy EC2 (terraform + aws cli + kubectl + ssh keys)
│   ├── setup-k8s-master.sh            <- kubeadm init on master
│   ├── setup-k8s-worker.sh            <- placeholder/docs for kubeadm join
│   └── verify-cluster.sh              <- sanity check kubectl get nodes
├── app/
│   ├── user-service/                  <- Spring Boot + JPA, /users REST API
│   │   ├── pom.xml, Dockerfile, .dockerignore
│   │   └── src/main + src/test (entity, repository, controller, seeder)
│   └── product-service/               <- Spring Boot + JPA, /products REST API
│       ├── pom.xml, Dockerfile, .dockerignore
│       └── src/main + src/test
├── k8s/                               <- numeric prefix = apply order
│   ├── 01-namespace.yaml              <- namespace: demo-app
│   ├── 02-user-db.yaml                <- Secret + Service + StatefulSet (Postgres)
│   ├── 03-product-db.yaml             <- Secret + Service + StatefulSet (Postgres)
│   ├── 04-user-service.yaml           <- Deployment + NodePort Service (30081)
│   └── 05-product-service.yaml        <- Deployment + NodePort Service (30082)
├── jenkins/
│   ├── Jenkinsfile                    <- builds both services in parallel
│   ├── plugins.txt
│   └── README-jenkins-setup.md
└── docs/architecture.md
```

---

## What you need (on your laptop)

- An **SSH client** (Windows: built-in OpenSSH or PuTTY; Mac/Linux: `ssh` already there).
- An **AWS account** with permission to launch EC2 instances and create IAM roles.
- A **Docker Hub account** for Jenkins to push images: <https://hub.docker.com>.
- A way to get this project onto the deploy EC2. Two options:
  - **Push to GitHub** (recommended — Jenkins also pulls from there later), or
  - **scp** the folder from your laptop after the deploy EC2 is up.

---

## End-to-end walkthrough

### Step 1 — Push this project to GitHub

The Jenkins EC2 will pull the source via SCM later, so it has to live in a Git repo somewhere. Create a public GitHub repo named `my-jenkins-k8s-project` and push this folder to it. (Private also works if you add credentials in Jenkins.)

If you'd rather not use GitHub, you can `scp -r` this folder to the deploy EC2 in step 4 — but you'll still need a Git repo for Jenkins, so GitHub is simpler.

### Step 2 — Create an IAM role for the deploy EC2

The deploy EC2 needs AWS permissions to create EC2, VPC, security groups, and key pairs. The clean way is an IAM role attached to the instance — no access keys needed.

In the AWS Console:
1. **IAM** → **Roles** → **Create role** → Trusted entity: **AWS service** → Use case: **EC2** → Next.
2. Attach policy: **AmazonEC2FullAccess** (sufficient for this lab; tighten for production).
3. Role name: `jenkins-k8s-deploy-role` → Create.

### Step 3 — Launch the deploy EC2 from the AWS Console

1. **EC2** → **Launch instance**.
2. Name: `jenkins-k8s-deploy`.
3. AMI: **Ubuntu Server 26.04 LTS** (HVM, EBS gp3). Free Tier eligible.
4. Instance type: **t3.micro** (free tier). It only runs terraform/ssh.
5. **Key pair** → Create new key pair → name `deploy-key` → RSA → `.pem` → Download. Save the `.pem` to your laptop (e.g. `~/Downloads/deploy-key.pem`).
6. **Network settings** → Create a security group that allows **SSH (port 22) from My IP**.
7. **Advanced details** → **IAM instance profile** → select `jenkins-k8s-deploy-role`.
8. **Launch instance**.

Wait ~30 seconds, copy the **public IPv4 address** from the instance details.

### Step 4 — SSH to the deploy EC2 and bootstrap it

From your laptop:

```bash
# Mac/Linux/Git Bash
chmod 400 ~/Downloads/deploy-key.pem
ssh -i ~/Downloads/deploy-key.pem ubuntu@<deploy_public_ip>
```

```powershell
# Windows PowerShell — fix permissions first if Windows complains
icacls $env:USERPROFILE\Downloads\deploy-key.pem /inheritance:r /grant:r "$($env:USERNAME):(R)"
ssh -i $env:USERPROFILE\Downloads\deploy-key.pem ubuntu@<deploy_public_ip>
```

**Once you're in the deploy EC2**, install all the tools:

```bash
# Clone the project (use your GitHub URL)
git clone https://github.com/<you>/my-jenkins-k8s-project.git
cd my-jenkins-k8s-project

# Bootstrap: installs terraform + aws cli + kubectl + generates ~/.ssh/jenkins_k8s_key
bash scripts/setup-deploy-server.sh

# Confirm AWS access works (returns your account/identity, no access keys needed thanks to the IAM role)
aws sts get-caller-identity
```

### Step 5 — Provision the Jenkins + K8s EC2s with Terraform

Still on the deploy EC2:

```bash
cd ~/my-jenkins-k8s-project/terraform
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
# The default values work as-is. The only one you MAY want to change:
#   public_key_path  - already correct ("~/.ssh/jenkins_k8s_key.pub") if you
#                      ran setup-deploy-server.sh
#
# If you want to tighten ssh_ingress_cidr to your laptop IP for security,
# remember to ALSO include the deploy EC2's public IP in that CIDR — otherwise
# the deploy server can't SSH/kubectl to the new EC2s. Easiest: leave at 0.0.0.0/0
# for the lab and lock down later.

terraform init
terraform apply -auto-approve
```

When apply finishes, Terraform prints the public/private IPs of the three new EC2s:

```
jenkins_public_ip      = "x.x.x.x"
jenkins_private_ip     = "10.x.x.x"
k8s_master_public_ip   = "y.y.y.y"
k8s_master_private_ip  = "10.x.x.x"
k8s_worker_public_ip   = "z.z.z.z"
```

> The user-data scripts on the new EC2s install Jenkins/Docker/kubectl on one box and containerd/kubeadm/kubelet on the others. **Wait ~5–8 minutes** for these to finish before continuing. To check whether user-data is finished:
>
> ```bash
> ssh -i ~/.ssh/jenkins_k8s_key -o StrictHostKeyChecking=no \
>     ubuntu@<ip> 'cloud-init status --wait && echo READY'
> ```
>
> The command blocks until cloud-init is done and prints `READY`. Run it once per new EC2.

### Step 6 — Initialize the Kubernetes cluster

From the **deploy EC2**, SSH to the master:

```bash
ssh -i ~/.ssh/jenkins_k8s_key -o StrictHostKeyChecking=no ubuntu@<k8s_master_public_ip>
```

On the master, clone the repo and run the init script:

```bash
git clone https://github.com/<you>/my-jenkins-k8s-project.git
cd my-jenkins-k8s-project
sudo bash scripts/setup-k8s-master.sh
```

This runs `kubeadm init`, installs Calico CNI, and **prints a `kubeadm join ...` command at the end** — copy it.

Open a **second terminal** on your laptop, SSH back to the deploy EC2, then to the worker:

```bash
ssh -i ~/Downloads/deploy-key.pem ubuntu@<deploy_public_ip>
ssh -i ~/.ssh/jenkins_k8s_key -o StrictHostKeyChecking=no ubuntu@<k8s_worker_public_ip>
sudo <paste-the-kubeadm-join-command-here>
```

Back on the master, verify both nodes are Ready:

```bash
kubectl get nodes
# NAME              STATUS   ROLES           AGE   VERSION
# ip-10-...master   Ready    control-plane   2m    v1.29.x
# ip-10-...worker   Ready    <none>          30s   v1.29.x
```

### Step 7 — Give Jenkins access to the cluster

Jenkins needs the master's kubeconfig so it can run `kubectl apply`. The flow:

```
  deploy EC2  --(scp key)-->  master  --(scp kubeconfig)-->  jenkins
```

**On the deploy EC2** — copy the SSH private key onto the master so the master can `scp` to Jenkins:

```bash
# (you should be on the deploy EC2, not the master)
scp -i ~/.ssh/jenkins_k8s_key ~/.ssh/jenkins_k8s_key \
    ubuntu@<k8s_master_public_ip>:~/.ssh/
```

**SSH to the master** and push kubeconfig over:

```bash
ssh -i ~/.ssh/jenkins_k8s_key ubuntu@<k8s_master_public_ip>

# (now on the master)
chmod 600 ~/.ssh/jenkins_k8s_key
scp -i ~/.ssh/jenkins_k8s_key -o StrictHostKeyChecking=no \
    ~/.kube/config ubuntu@<jenkins_private_ip>:/tmp/kubeconfig
exit
```

**SSH to the Jenkins EC2** (from the deploy server) and install the kubeconfig:

```bash
ssh -i ~/.ssh/jenkins_k8s_key ubuntu@<jenkins_public_ip>

# (now on the Jenkins EC2)
sudo mkdir -p /var/lib/jenkins/.kube
sudo cp /tmp/kubeconfig /var/lib/jenkins/.kube/config
sudo chown -R jenkins:jenkins /var/lib/jenkins/.kube

# kubeadm normally writes the master's PRIVATE IP — verify:
sudo grep '^    server:' /var/lib/jenkins/.kube/config
# Expected:  server: https://<master-private-ip>:6443
# If the address is 127.0.0.1 or a hostname Jenkins can't resolve, fix it:
#   sudo sed -i 's|server: https://.*:6443|server: https://<master-private-ip>:6443|' \
#       /var/lib/jenkins/.kube/config

# Smoke test
sudo -u jenkins kubectl get nodes      # should list both nodes
exit
```

### Step 8 — Configure Jenkins (in the browser)

Open `http://<jenkins_public_ip>:8080` in a browser on your laptop. (The Terraform-created security group already opens 8080 to your IP if you set `jenkins_ingress_cidr`.)

1. **Initial admin password** — back on the Jenkins EC2:
   ```bash
   sudo cat /var/lib/jenkins/secrets/initialAdminPassword
   ```
2. **Install suggested plugins**, then **Manage Jenkins → Plugins → Available** and install: `Docker Pipeline`, `Kubernetes CLI`, `Pipeline Utility Steps`. (Full list: [jenkins/plugins.txt](jenkins/plugins.txt))
3. **Add Docker Hub credentials** — Manage Jenkins → Credentials → System → Global → Add:
   - Kind: **Username with password**
   - Username: your Docker Hub username
   - Password: your Docker Hub password (or access token)
   - **ID: `dockerhub-creds`** (must match exactly)
4. **Make sure jenkins user can use Docker** (back on the Jenkins EC2):
   ```bash
   sudo usermod -aG docker jenkins
   sudo systemctl restart jenkins
   sudo -u jenkins docker ps     # must NOT print a permission error
   ```

Full setup detail: [jenkins/README-jenkins-setup.md](jenkins/README-jenkins-setup.md).

### Step 9 — Create the pipeline job and run it

In the Jenkins UI:
1. **New Item** → name `demo-app-cicd` → Pipeline → OK.
2. Scroll to **Pipeline** section:
   - Definition: **Pipeline script from SCM**
   - SCM: **Git**
   - Repository URL: `https://github.com/<you>/my-jenkins-k8s-project.git`
   - Branch: `*/main`
   - Script Path: `jenkins/Jenkinsfile`
3. (Optional) Under **General** → **This project is parameterized** → Add String Parameter `DOCKERHUB_USER` with your Docker Hub username. Otherwise edit the default in [jenkins/Jenkinsfile](jenkins/Jenkinsfile).
4. **Save** → **Build Now**.

The pipeline:
1. Checks out the repo.
2. **In parallel**: runs `mvn clean package` for both `user-service` and `product-service` (build + unit tests using H2).
3. **In parallel**: `docker build` produces `<user>/user-service:<build-number>` and `<user>/product-service:<build-number>`.
4. `docker push` both images to Docker Hub.
5. `sed`s the new image tags into [k8s/04-user-service.yaml](k8s/04-user-service.yaml) and [k8s/05-product-service.yaml](k8s/05-product-service.yaml), then `kubectl apply -f k8s/rendered/` (namespace → DBs → app services).
6. Waits for both StatefulSets and Deployments to finish rolling out.

### Step 10 — Verify the deployment

On the **master**:

```bash
kubectl get pods,svc,statefulset -n demo-app
# Expected:
#   pod/user-postgres-0           1/1 Running
#   pod/product-postgres-0        1/1 Running
#   pod/user-service-xxx          1/1 Running   (x2)
#   pod/product-service-xxx       1/1 Running   (x2)
#   svc/user-postgres   ClusterIP  None         5432/TCP
#   svc/product-postgres ClusterIP None         5432/TCP
#   svc/user-service    NodePort   10.x.x.x     80:30081/TCP
#   svc/product-service NodePort   10.x.x.x     80:30082/TCP
```

Hit each service from your laptop's browser or curl:

```bash
# Pre-seeded users
curl http://<k8s_worker_public_ip>:30081/users
# [{"id":1,"name":"Alice","email":"alice@example.com"},
#  {"id":2,"name":"Bob","email":"bob@example.com"}]

# Pre-seeded products
curl http://<k8s_worker_public_ip>:30082/products
# [{"id":1,"name":"Keyboard","price":49.99,"stock":100}, ...]

# Create a new user (data persists in Postgres across pod restarts)
curl -X POST http://<k8s_worker_public_ip>:30081/users \
  -H 'Content-Type: application/json' \
  -d '{"name":"Carol","email":"carol@example.com"}'

# Get one
curl http://<k8s_worker_public_ip>:30081/users/3
```

### Step 11 — Iterate

Edit code in `app/user-service/` or `app/product-service/`, push to GitHub, click **Build Now** in Jenkins. New images, rolling update — watch with:

```bash
kubectl get pods -n demo-app -w
```

Data in the Postgres PVCs survives pod restarts and rolling updates.

---

## Cleanup (avoid AWS charges)

From the **deploy EC2**:

```bash
cd ~/my-jenkins-k8s-project/terraform
terraform destroy -auto-approve
```

Then in the AWS Console, **terminate the deploy EC2** itself (Terraform doesn't manage it — you launched it manually). Optionally delete the IAM role and the `deploy-key` key pair.

---

## Cost estimate

| Component | Type | Approx \$ /month (24x7) |
|---|---|---|
| Deploy EC2 | t3.micro (free tier eligible) | \$0 – \$8 |
| Jenkins EC2 | t3.medium | \$30 |
| K8s master | t3.medium | \$30 |
| K8s worker | t3.medium | \$30 |
| **Total** | | **~\$90** |

Stop the instances or `terraform destroy` after each lab session.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `terraform apply`: `NoCredentialProviders` | IAM role not attached to the deploy EC2. AWS Console → EC2 → select instance → Actions → Security → Modify IAM role → pick `jenkins-k8s-deploy-role`. |
| `terraform apply` errors on `public_key_path` | Path must be the `.pub` file `setup-deploy-server.sh` generated. Default: `/home/ubuntu/.ssh/jenkins_k8s_key.pub`. |
| Can't SSH right after `terraform apply` | User-data is still running. Wait 5–8 min; check `/var/log/cloud-init-output.log` on the new EC2. |
| `kubectl get nodes` shows NotReady | Calico didn't apply. Re-run the `kubectl apply -f .../calico.yaml` line from [scripts/setup-k8s-master.sh](scripts/setup-k8s-master.sh). |
| Jenkins build fails on `docker: permission denied` | `jenkins` user not in docker group — Step 8.4. |
| Jenkins build fails on `kubectl: connection refused` | kubeconfig server: address wrong. Edit it to the master's **private** IP (Step 7). |
| `kubeadm join` fails — port 6443 unreachable | Security group blocking inter-node — check [terraform/security-groups.tf](terraform/security-groups.tf). |
| Pods stuck in `ImagePullBackOff` | Docker Hub repo private. Make it public, or add an `imagePullSecret` to the Deployment. |
| `user-service` / `product-service` pod stuck in `Init:0/1` | The `wait-for-postgres` init container is blocked because Postgres isn't ready. Check `kubectl -n demo-app get pods` — the matching `user-postgres-0` / `product-postgres-0` should be Running. If not, `kubectl describe statefulset/...` for clues (often a missing PVC because the cluster has no default StorageClass). |
| `kubectl get pvc -n demo-app` shows `Pending` forever | No default StorageClass. On kubeadm clusters install one — easiest is the local-path-provisioner: `kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml && kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'`. Then delete and recreate the StatefulSet pods. |
| App logs show `password authentication failed` | The Spring Boot pod and the matching Postgres are reading from different Secrets. Double-check the Secret names in `04-user-service.yaml` / `05-product-service.yaml` match `02-user-db.yaml` / `03-product-db.yaml`. |
| Want to inspect Postgres data | `kubectl -n demo-app exec -it user-postgres-0 -- psql -U useradmin -d users` then `\dt` and `SELECT * FROM users;` |
| Lost the `kubeadm join` command | Regenerate on master: `sudo kubeadm token create --print-join-command`. |
| `Permission denied (publickey)` SSHing master→worker | Copy `jenkins_k8s_key` (private) onto the master with `scp` from the deploy EC2 first. |
| Deploy EC2 can't SSH to the new EC2s after locking down `ssh_ingress_cidr` | The CIDR must include the deploy EC2's public IP. Easiest fix: set `ssh_ingress_cidr = "0.0.0.0/0"` and `terraform apply` again. |
| `terraform apply` fails on `file()` for `public_key_path` | Path doesn't exist yet — run `bash scripts/setup-deploy-server.sh` first to generate the key. |

See [docs/architecture.md](docs/architecture.md) for component diagrams and design decisions.
