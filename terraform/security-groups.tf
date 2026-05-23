data "aws_vpc" "default" {
  default = true
}

# ---------- Jenkins server SG ----------
resource "aws_security_group" "jenkins" {
  name        = "${var.project_name}-jenkins-sg"
  description = "Allow SSH and Jenkins UI"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_ingress_cidr]
  }

  ingress {
    description = "Jenkins UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.jenkins_ingress_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-jenkins-sg"
    Project = var.project_name
  }
}

# ---------- K8s nodes SG ----------
# Shared between master and worker so they can talk to each other freely.
resource "aws_security_group" "k8s" {
  name        = "${var.project_name}-k8s-sg"
  description = "K8s control plane + worker traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_ingress_cidr]
  }

  ingress {
    description = "K8s API server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.ssh_ingress_cidr]
  }

  ingress {
    description = "NodePort services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.nodeport_ingress_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-k8s-sg"
    Project = var.project_name
  }
}

# Allow all traffic between members of the k8s SG (kubelet, etcd, calico, etc.)
resource "aws_security_group_rule" "k8s_intra_sg" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.k8s.id
  source_security_group_id = aws_security_group.k8s.id
  description              = "Allow all traffic between K8s nodes"
}

# Let Jenkins reach the K8s API server on the master's private IP
resource "aws_security_group_rule" "k8s_from_jenkins" {
  type                     = "ingress"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.k8s.id
  source_security_group_id = aws_security_group.jenkins.id
  description              = "Allow Jenkins to call K8s API"
}
