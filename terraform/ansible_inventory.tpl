all:
  children:
    swarm_manager:
      hosts:
        manager:
          ansible_host: ${manager_public_ip}
          private_ip: ${manager_private_ip}
    swarm_workers:
      hosts:
        worker1:
          ansible_host: ${worker1_public_ip}
          private_ip: ${worker1_private_ip}
        worker2:
          ansible_host: ${worker2_public_ip}
          private_ip: ${worker2_private_ip}
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: ~/.ssh/your-key.pem
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
