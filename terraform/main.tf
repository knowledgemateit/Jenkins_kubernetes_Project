data "aws_ami" "ubuntu_2204" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "this" {
  key_name   = var.key_name
  public_key = file(pathexpand(var.public_key_path))
}

# ---------- Jenkins server ----------
resource "aws_instance" "jenkins" {
  ami                         = data.aws_ami.ubuntu_2204.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.this.key_name
  vpc_security_group_ids      = [aws_security_group.jenkins.id]
  associate_public_ip_address = true

  user_data = file("${path.module}/user-data/jenkins-bootstrap.sh")

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.project_name}-jenkins"
    Role    = "jenkins"
    Project = var.project_name
  }
}

# ---------- K8s master ----------
resource "aws_instance" "k8s_master" {
  ami                         = data.aws_ami.ubuntu_2204.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.this.key_name
  vpc_security_group_ids      = [aws_security_group.k8s.id]
  associate_public_ip_address = true

  user_data = file("${path.module}/user-data/k8s-common-bootstrap.sh")

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.project_name}-k8s-master"
    Role    = "k8s-master"
    Project = var.project_name
  }
}

# ---------- K8s worker ----------
resource "aws_instance" "k8s_worker" {
  ami                         = data.aws_ami.ubuntu_2204.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.this.key_name
  vpc_security_group_ids      = [aws_security_group.k8s.id]
  associate_public_ip_address = true

  user_data = file("${path.module}/user-data/k8s-common-bootstrap.sh")

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.project_name}-k8s-worker"
    Role    = "k8s-worker"
    Project = var.project_name
  }
}
