output "jenkins_public_ip" {
  description = "Public IP of the Jenkins server. Open http://<this>:8080 in a browser."
  value       = aws_instance.jenkins.public_ip
}

output "jenkins_private_ip" {
  description = "Private IP of the Jenkins server (used in security group rules)."
  value       = aws_instance.jenkins.private_ip
}

output "k8s_master_public_ip" {
  description = "Public IP of the K8s control-plane node."
  value       = aws_instance.k8s_master.public_ip
}

output "k8s_master_private_ip" {
  description = "Private IP of the K8s control-plane node. Used in the kubeconfig server: address."
  value       = aws_instance.k8s_master.private_ip
}

output "k8s_worker_public_ip" {
  description = "Public IP of the K8s worker node. Hit NodePort services here."
  value       = aws_instance.k8s_worker.public_ip
}

output "ssh_jenkins" {
  description = "Convenience SSH command for the Jenkins server"
  value       = "ssh -i <your-private-key> ubuntu@${aws_instance.jenkins.public_ip}"
}

output "ssh_k8s_master" {
  description = "Convenience SSH command for the K8s master"
  value       = "ssh -i <your-private-key> ubuntu@${aws_instance.k8s_master.public_ip}"
}

output "ssh_k8s_worker" {
  description = "Convenience SSH command for the K8s worker"
  value       = "ssh -i <your-private-key> ubuntu@${aws_instance.k8s_worker.public_ip}"
}
