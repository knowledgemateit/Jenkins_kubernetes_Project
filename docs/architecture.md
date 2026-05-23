# Architecture

## Components

### Infrastructure layer (4 EC2 instances)

```
                    +-----------------------------+
                    |  Developer laptop           |
                    |  - ssh client only          |
                    +--------------+--------------+
                                   | ssh
                                   v
                    +-----------------------------+
                    |  Deploy EC2 (t3.micro)      |
                    |  - terraform                |
                    |  - aws cli (uses IAM role)  |
                    |  - kubectl                  |
                    |  - generates SSH keypair    |
                    +--------------+--------------+
                                   |
                                   | terraform apply
                                   v
                  +----------------+-----------------+
                  |              AWS EC2             |
                  |  default VPC, t3.medium x 3      |
                  +----------------+-----------------+
                                   |
        +--------------------------+--------------------------+
        |                          |                          |
        v                          v                          v
+----------------+      +-------------------+      +-------------------+
|  Jenkins EC2   |      |   K8s master EC2  |      |   K8s worker EC2  |
|----------------|      |-------------------|      |-------------------|
| Java 17        |      | containerd        |      | containerd        |
| Jenkins LTS    |      | kubeadm/kubelet   |      | kubeadm/kubelet   |
| Docker engine  |      | API server :6443  |      | kubelet :10250    |
| kubectl        |      | etcd, scheduler   |      | (joined to master)|
| Maven, git     |      | Calico CNI        |      | Calico CNI        |
| port 8080      |      | local-path SC     |      | NodePort 30081/82 |
+----------------+      +-------------------+      +-------------------+
```

### Workload layer (inside the K8s cluster)

```
                       Namespace: demo-app
   +------------------------------------------------------------------+
   |                                                                  |
   |  +-------------------+              +-------------------+        |
   |  | user-service      |              | product-service   |        |
   |  | Deployment        |              | Deployment        |        |
   |  | replicas: 2       |              | replicas: 2       |        |
   |  | initContainer:    |              | initContainer:    |        |
   |  |   wait-for-postgres              |   wait-for-postgres        |
   |  | env: DB_*         |              | env: DB_*         |        |
   |  |   from secrets    |              |   from secrets    |        |
   |  +---------+---------+              +---------+---------+        |
   |            | JDBC                             | JDBC             |
   |            | (cluster DNS:                    | (cluster DNS:    |
   |            |  user-postgres:5432)             |  product-postgres:5432)
   |            v                                  v                  |
   |  +-------------------+              +-------------------+        |
   |  | user-postgres     |              | product-postgres  |        |
   |  | StatefulSet       |              | StatefulSet       |        |
   |  | Postgres 16       |              | Postgres 16       |        |
   |  | PVC: 2Gi          |              | PVC: 2Gi          |        |
   |  | (local-path SC)   |              | (local-path SC)   |        |
   |  +-------------------+              +-------------------+        |
   |                                                                  |
   |  Secrets:                                                        |
   |    user-db-secret    -> POSTGRES_DB=users     POSTGRES_USER=...  |
   |    product-db-secret -> POSTGRES_DB=products  POSTGRES_USER=...  |
   |                                                                  |
   +-------+----------------------------------------------+-----------+
           ^                                              ^
           | NodePort 30081                               | NodePort 30082
        external                                       external
```

## Why these choices

- **Self-managed kubeadm cluster (not EKS):** chosen for learning value. EKS would hide the control plane setup, which is the most instructive part.
- **3 workload EC2s + 1 deploy EC2:** smallest split that's still realistic. Deploy box is t3.micro (free tier); workload nodes are t3.medium (kubeadm needs ≥ 2 vCPU on the master).
- **Calico CNI:** popular default that supports network policies. Pod CIDR `192.168.0.0/16` is Calico's default.
- **local-path-provisioner StorageClass:** kubeadm ships with no default StorageClass, so PVCs hang forever. local-path is the smallest fix — uses node-local disk, fine for a lab. Production would use EBS-CSI / Rook / Longhorn.
- **One Postgres per service (database-per-service pattern):** classic microservices pattern — services own their schema, can evolve independently. Two StatefulSets, two PVCs, two Secrets.
- **Database credentials in Secrets, mounted as env vars:** Spring Boot's `${DB_PASSWORD}` placeholder reads from env. `envFrom: secretRef` on the Postgres pod, individual `secretKeyRef`s on the app pod (so we can also surface DB_HOST/DB_PORT as plain env values).
- **Headless Service for Postgres (`clusterIP: None`):** standard for StatefulSets — gives stable DNS like `user-postgres-0.user-postgres.demo-app.svc.cluster.local` while still letting the app target the short name `user-postgres:5432`.
- **`wait-for-postgres` init container:** Spring Boot fails fast on DB unavailable. Waiting in an init container is cleaner than tuning Hikari retry timeouts.
- **NodePort 30081/30082:** cheapest exposure on EC2 (no LoadBalancer cost). Production would use Ingress + ALB.
- **Docker Hub registry:** zero AWS-side setup. ECR is more realistic but adds IAM and credential plumbing.
- **`spring.jpa.hibernate.ddl-auto=update`:** quick start without migrations. Production should use Flyway/Liquibase.
- **Sample dev passwords committed in `02-user-db.yaml` / `03-product-db.yaml`:** intentional for the lab. See "Production hardening" below.

## CI/CD flow

```
git push                           Jenkins polls/webhook
  |                                       |
  v                                       v
+---------+  webhook   +----------------------------------------------+
|  Repo   | ---------> |  Jenkins EC2                                 |
+---------+            |  Stage: Build & Test (parallel)              |
                       |    - mvn package: user-service               |
                       |    - mvn package: product-service            |
                       |  Stage: Docker Build (parallel)              |
                       |    - docker build user-service               |
                       |    - docker build product-service            |
                       |  Stage: Docker Push                          |
                       |    - push both images to Docker Hub          |
                       |  Stage: Deploy to Kubernetes                 |
                       |    - sed image tags into manifests           |
                       |    - kubectl apply -f k8s/rendered/          |
                       |    - rollout status x4                       |
                       +-----------------+----------------------------+
                                         |
                                         v
                                +--------+---------+
                                | K8s master :6443 |
                                +--------+---------+
                                         |
                                         v
                                +-----------------------+
                                | K8s worker            |
                                | user-service x2       |
                                | product-service x2    |
                                | user-postgres x1      |
                                | product-postgres x1   |
                                | NodePort 30081 / 30082|
                                +-----------------------+
```

## File-level responsibilities

| Path | Responsibility |
|---|---|
| [terraform/main.tf](../terraform/main.tf) | Defines the 3 workload EC2 instances, key pair, AMI lookup |
| [terraform/security-groups.tf](../terraform/security-groups.tf) | Firewall — Jenkins :8080, K8s :6443/:30000-32767, intra-cluster |
| [terraform/user-data/jenkins-bootstrap.sh](../terraform/user-data/jenkins-bootstrap.sh) | Installs Jenkins + Docker + kubectl on first boot |
| [terraform/user-data/k8s-common-bootstrap.sh](../terraform/user-data/k8s-common-bootstrap.sh) | Installs containerd + kubeadm/kubelet on master and worker |
| [scripts/setup-deploy-server.sh](../scripts/setup-deploy-server.sh) | Bootstraps the deploy EC2 (terraform, aws cli, kubectl, ssh key) |
| [scripts/setup-k8s-master.sh](../scripts/setup-k8s-master.sh) | `kubeadm init` + Calico + local-path StorageClass + prints join command |
| [app/user-service/](../app/user-service/) | Spring Boot + JPA + Postgres, `/users` REST API |
| [app/product-service/](../app/product-service/) | Spring Boot + JPA + Postgres, `/products` REST API |
| [k8s/01-namespace.yaml](../k8s/01-namespace.yaml) | Creates the `demo-app` namespace |
| [k8s/02-user-db.yaml](../k8s/02-user-db.yaml) | Postgres for user-service: Secret + headless Service + StatefulSet + PVC |
| [k8s/03-product-db.yaml](../k8s/03-product-db.yaml) | Postgres for product-service |
| [k8s/04-user-service.yaml](../k8s/04-user-service.yaml) | user-service Deployment + NodePort Service (30081), placeholder image |
| [k8s/05-product-service.yaml](../k8s/05-product-service.yaml) | product-service Deployment + NodePort Service (30082), placeholder image |
| [jenkins/Jenkinsfile](../jenkins/Jenkinsfile) | Parallel build/test/image, push, kubectl apply with `sed`-rendered manifests |

## Production hardening checklist

The current setup is for learning. Before using anywhere real:

- [ ] **Lock all `0.0.0.0/0` ingress** to your IP only — including `ssh_ingress_cidr` (must include the deploy EC2's public IP).
- [ ] **Stop committing Secrets.** Generate them at deploy time with `kubectl create secret generic ... --from-literal=...` or use a Sealed Secrets / External Secrets / SOPS workflow.
- [ ] **Replace local-path with EBS-CSI**. local-path data lives on the node's disk — losing the worker EC2 loses the data.
- [ ] **Use Flyway or Liquibase** for schema migrations. `ddl-auto=update` is fine for demos, dangerous in production.
- [ ] **Run Jenkins agents on K8s** (Kubernetes plugin) instead of building on the controller — better isolation and parallelism.
- [ ] **Use IAM Roles for Service Accounts (IRSA) + ECR** instead of Docker Hub.
- [ ] **Replace NodePort with Ingress + ALB** behind HTTPS / cert-manager.
- [ ] **Snapshot etcd**; back up Postgres PVCs (Velero / pg_dump CronJob).
- [ ] **Custom VPC** with private subnets and a bastion host instead of the default VPC.
- [ ] **Pin all package versions** in user-data scripts (kubeadm, calico, postgres image tags).
- [ ] **NetworkPolicy** to restrict which pods can reach each Postgres (only the matching service should be allowed).
- [ ] **Resource quotas + LimitRanges** on the namespace.
