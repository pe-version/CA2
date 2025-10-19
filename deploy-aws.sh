#!/bin/bash
set -e

echo "=========================================="
echo "CA2 AWS Deployment - Terraform + Ansible"
echo "=========================================="
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v terraform &> /dev/null; then
    echo "Error: terraform not found"
    exit 1
fi

if ! command -v ansible &> /dev/null; then
    echo "Error: ansible not found"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo "Error: aws CLI not found"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites met${NC}"
echo ""

# Step 1: Terraform
echo -e "${BLUE}Step 1: Provisioning AWS Infrastructure${NC}"
cd terraform/

if [ ! -f terraform.tfvars ]; then
    echo -e "${YELLOW}Warning: terraform.tfvars not found${NC}"
    echo "Copy terraform.tfvars.example to terraform.tfvars and update it"
    exit 1
fi

terraform init
terraform plan
echo ""
read -p "Apply Terraform plan? (yes/no) " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Cancelled"
    exit 0
fi

terraform apply -auto-approve

echo -e "${GREEN}✓ Infrastructure provisioned${NC}"
echo ""

# Generate Ansible inventory
echo -e "${BLUE}Generating Ansible inventory...${NC}"
terraform output -raw ansible_inventory > ../ansible/inventory/aws_hosts.yml

echo -e "${GREEN}✓ Inventory generated${NC}"
echo ""

# Display connection info
echo "SSH Connection Strings:"
terraform output -json ssh_connection_strings | jq -r 'to_entries[] | "\(.key): \(.value)"'
echo ""

cd ..

# Step 2: Wait for instances to be ready
echo -e "${BLUE}Step 2: Waiting for instances to be ready${NC}"
sleep 30

# Step 3: Ansible - Setup Swarm
echo -e "${BLUE}Step 3: Setting up Docker Swarm${NC}"
cd ansible/

# Test connectivity
echo "Testing SSH connectivity..."
ansible all -i inventory/aws_hosts.yml -m ping

echo ""
echo "Installing Docker and configuring Swarm..."
ansible-playbook -i inventory/aws_hosts.yml swarm-setup.yml

echo -e "${GREEN}✓ Docker Swarm configured${NC}"
echo ""

# Step 4: Deploy Stack
echo -e "${BLUE}Step 4: Deploying Metals Pipeline Stack${NC}"
ansible-playbook -i inventory/aws_hosts.yml deploy-stack.yml

echo -e "${GREEN}✓ Stack deployed${NC}"
echo ""

cd ..

# Display final info
echo "=========================================="
echo -e "${GREEN}Deployment Complete!${NC}"
echo "=========================================="
echo ""

cd terraform/
MANAGER_IP=$(terraform output -raw manager_public_ip)
cd ..

echo "Health Check URLs:"
echo "  Producer:  http://${MANAGER_IP}:8000/health"
echo "  Processor: http://${MANAGER_IP}:8001/health"
echo ""

echo "Test health endpoints:"
echo "  curl http://${MANAGER_IP}:8000/health"
echo "  curl http://${MANAGER_IP}:8001/health"
echo ""

echo "SSH to manager:"
echo "  ssh -i ~/.ssh/your-key.pem ubuntu@${MANAGER_IP}"
echo ""

echo "View stack status:"
echo "  ssh -i ~/.ssh/your-key.pem ubuntu@${MANAGER_IP} 'docker stack ps metals-pipeline'"
echo ""
