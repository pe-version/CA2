#!/bin/bash
set -e

echo "=========================================="
echo "CA2 AWS Cleanup - Terraform + Ansible"
echo "=========================================="
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}WARNING: This will destroy all AWS resources${NC}"
read -p "Continue? (yes/NO) " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Cancelled"
    exit 0
fi

# Step 1: Destroy Stack via Ansible
echo "Step 1: Removing Docker Stack..."
cd ansible/

if [ -f inventory/aws_hosts.yml ]; then
    echo "Removing stack from Swarm..."
    ansible-playbook -i inventory/aws_hosts.yml destroy-stack.yml
    echo -e "${GREEN}✓ Stack removed${NC}"
else
    echo -e "${YELLOW}⚠ Inventory not found, skipping stack removal${NC}"
fi

cd ..

# Step 2: Destroy Infrastructure
echo ""
echo "Step 2: Destroying AWS Infrastructure..."
cd terraform/

terraform destroy -auto-approve

echo -e "${GREEN}✓ Infrastructure destroyed${NC}"

cd ..

# Clean up generated files
echo ""
echo "Cleaning up generated files..."
rm -f ansible/inventory/aws_hosts.yml

echo ""
echo "=========================================="
echo -e "${GREEN}Cleanup Complete!${NC}"
echo "=========================================="
