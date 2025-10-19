output "manager_public_ip" {
  description = "Public IP of manager node"
  value       = aws_instance.swarm_manager.public_ip
}

output "manager_private_ip" {
  description = "Private IP of manager node"
  value       = aws_instance.swarm_manager.private_ip
}

output "worker_1_public_ip" {
  description = "Public IP of worker 1"
  value       = aws_instance.swarm_worker_1.public_ip
}

output "worker_1_private_ip" {
  description = "Private IP of worker 1"
  value       = aws_instance.swarm_worker_1.private_ip
}

output "worker_2_public_ip" {
  description = "Public IP of worker 2"
  value       = aws_instance.swarm_worker_2.public_ip
}

output "worker_2_private_ip" {
  description = "Private IP of worker 2"
  value       = aws_instance.swarm_worker_2.private_ip
}

output "ansible_inventory" {
  description = "Ansible inventory in YAML format"
  value = templatefile("${path.module}/ansible_inventory.tpl", {
    manager_public_ip  = aws_instance.swarm_manager.public_ip
    manager_private_ip = aws_instance.swarm_manager.private_ip
    worker1_public_ip  = aws_instance.swarm_worker_1.public_ip
    worker1_private_ip = aws_instance.swarm_worker_1.private_ip
    worker2_public_ip  = aws_instance.swarm_worker_2.public_ip
    worker2_private_ip = aws_instance.swarm_worker_2.private_ip
  })
}

output "ssh_connection_strings" {
  description = "SSH connection commands"
  value = {
    manager = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ubuntu@${aws_instance.swarm_manager.public_ip}"
    worker1 = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ubuntu@${aws_instance.swarm_worker_1.public_ip}"
    worker2 = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ubuntu@${aws_instance.swarm_worker_2.public_ip}"
  }
}

output "health_check_urls" {
  description = "Health check endpoints"
  value = {
    producer  = "http://${aws_instance.swarm_manager.public_ip}:8000/health"
    processor = "http://${aws_instance.swarm_manager.public_ip}:8001/health"
  }
}
