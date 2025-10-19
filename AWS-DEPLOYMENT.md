# AWS Deployment Guide - 3-Node Docker Swarm

## Overview

This guide deploys the CA2 Metals Pipeline on a **3-node Docker Swarm cluster** in AWS using:
- **Terraform** for infrastructure provisioning
- **Ansible** for configuration management and application deployment

## Directory Structure

```
CA2/
├── terraform/
│   ├── main.tf                    # AWS infrastructure
│   ├── variables.tf               # Input variables
│   ├── outputs.tf                 # Outputs and inventory template
│   ├── ansible_inventory.tpl      # Ansible inventory template
│   ├── terraform.tfvars.example   # Example variables
│   └── terraform.tfvars           # Your actual values (gitignored)
│
├── ansible/
│   ├── inventory/
│   │   └── aws_hosts.yml          # Generated from Terraform
│   ├── swarm-setup.yml            # Docker + Swarm setup
│   ├── deploy-stack.yml           # Deploy application
│   └── destroy-stack.yml          # Remove application
│
├── deploy-aws.sh                  # Main deployment script
├── destroy-aws.sh                 # Cleanup script
└── docker-compose.yml             # Application stack definition
```

## Prerequisites

### 1. AWS Account Setup

- AWS account with permissions to create EC2, VPC, Security Groups
- AWS CLI installed and configured:
  ```bash
  aws configure
  # Enter: Access Key, Secret Key, Region (us-east-2), Output (json)
  ```

### 2. SSH Key Pair

Create an SSH key pair in AWS EC2:
1. Go to AWS Console → EC2 → Key Pairs
2. Create Key Pair (e.g., `ca2-swarm-key`)
3. Download the `.pem` file
4. Move to `~/.ssh/` and set permissions:
   ```bash
   mv ~/Downloads/ca2-swarm-key.pem ~/.ssh/
   chmod 400 ~/.ssh/ca2-swarm-key.pem
   ```

### 3. Required Tools

```bash
# Terraform
brew install terraform

# Ansible
brew install ansible

# AWS CLI
brew install awscli

# jq (for JSON parsing)
brew install jq
```

### 4. Verify Prerequisites

```bash
terraform --version   # Should be >= 1.5.0
ansible --version     # Should be >= 2.9
aws --version         # Should be >= 2.0
```

## Setup Steps

### Step 1: Configure Terraform Variables

```bash
cd terraform/

# Copy example file
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

Update these values:
```hcl
aws_region     = "us-east-2"
ssh_key_name   = "ca2-swarm-key"  # Your AWS key pair name (without .pem)
instance_type  = "t3.small"
ami_id         = "ami-0ea3c35c5c3284d82"  # Ubuntu 22.04 in us-east-2
```

### Step 2: Update Registry Username

Edit `ansible/deploy-stack.yml`:
```yaml
vars:
  registry_username: YOUR_DOCKERHUB_USERNAME  # Change this!
```

### Step 3: Update Ansible Inventory Template

Edit `terraform/ansible_inventory.tpl`:
```yaml
vars:
  ansible_ssh_private_key_file: ~/.ssh/ca2-swarm-key.pem  # Your key name
```

### Step 4: Make Scripts Executable

```bash
chmod +x deploy-aws.sh destroy-aws.sh
```

## Deployment

### Full Automated Deployment

```bash
# Run the complete deployment
./deploy-aws.sh
```

This script will:
1. ✅ Provision 3 EC2 instances (1 manager + 2 workers)
2. ✅ Create VPC, subnets, security groups
3. ✅ Generate Ansible inventory from Terraform outputs
4. ✅ Install Docker on all nodes
5. ✅ Initialize Docker Swarm
6. ✅ Join workers to the swarm
7. ✅ Deploy the metals pipeline stack
8. ✅ Display health check URLs

### Manual Step-by-Step Deployment

If you prefer to run each step manually:

#### 1. Provision Infrastructure

```bash
cd terraform/

# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Apply
terraform apply

# View outputs
terraform output
```

#### 2. Generate Ansible Inventory

```bash
# Still in terraform/
terraform output -raw ansible_inventory > ../ansible/inventory/aws_hosts.yml

# Verify
cat ../ansible/inventory/aws_hosts.yml
```

#### 3. Test SSH Connectivity

```bash
cd ../ansible/

# Test connection to all nodes
ansible all -i inventory/aws_hosts.yml -m ping

# Should see SUCCESS for all 3 nodes
```

#### 4. Setup Docker Swarm

```bash
# Install Docker and configure Swarm
ansible-playbook -i inventory/aws_hosts.yml swarm-setup.yml
```

This playbook:
- Installs Docker on all nodes
- Initializes Swarm on manager
- Joins workers to the cluster
- Verifies 3-node cluster

#### 5. Deploy Application Stack

```bash
# Deploy the metals pipeline
ansible-playbook -i inventory/aws_hosts.yml deploy-stack.yml
```

This playbook:
- Copies application files to manager
- Creates Docker secrets
- Deploys the stack
- Waits for services to start

## Verification

### 1. Check Infrastructure

```bash
cd terraform/
terraform output

# Should show:
# - manager_public_ip
# - worker_1_public_ip  
# - worker_2_public_ip
# - Health check URLs
```

### 2. SSH to Manager

```bash
# Get manager IP
MANAGER_IP=$(cd terraform && terraform output -raw manager_public_ip)

# SSH in
ssh -i ~/.ssh/ca2-swarm-key.pem ubuntu@$MANAGER_IP

# Check Swarm cluster
docker node ls

# Should show 3 nodes:
# ID            HOSTNAME   STATUS   AVAILABILITY   MANAGER STATUS
# abc123 *      manager    Ready    Active         Leader
# def456        worker1    Ready    Active
# ghi789        worker2    Ready    Active

# Check services
docker stack services metals-pipeline

# Check tasks
docker stack ps metals-pipeline
```

### 3. Test Health Endpoints

```bash
# From your local machine
MANAGER_IP=$(cd terraform && terraform output -raw manager_public_ip)

# Test producer
curl http://$MANAGER_IP:8000/health

# Expected: {"status": "healthy", "kafka_connected": true, ...}

# Test processor
curl http://$MANAGER_IP:8001/health

# Expected: {"status": "healthy", "mongodb_status": "connected", ...}
```

### 4. Verify Service Distribution

```bash
# SSH to manager
ssh -i ~/.ssh/ca2-swarm-key.pem ubuntu@$MANAGER_IP

# Check which nodes are running which services
docker service ps metals-pipeline_producer
docker service ps metals-pipeline_processor
docker service ps metals-pipeline_mongodb

# Should see services distributed across nodes
```

### 5. Run Scaling Test

```bash
# On manager node
cd /home/ubuntu/ca2-deployment

# Scale producers
docker service scale metals-pipeline_producer=5

# Wait a moment
sleep 30

# Check distribution
docker service ps metals-pipeline_producer

# Should see 5 replicas across the 3 nodes
```

## Monitoring

### View Logs

```bash
# SSH to manager
ssh -i ~/.ssh/ca2-swarm-key.pem ubuntu@$MANAGER_IP

# View service logs
docker service logs metals-pipeline_producer
docker service logs metals-pipeline_processor
docker service logs metals-pipeline_kafka
docker service logs metals-pipeline_mongodb

# Follow logs
docker service logs -f metals-pipeline_processor
```

### Service Status

```bash
# List services
docker service ls

# Detailed service info
docker service inspect metals-pipeline_producer --pretty

# Task status
docker stack ps metals-pipeline --no-trunc
```

### Resource Usage

```bash
# On manager
docker stats

# Node info
docker node inspect self --pretty
```

## Cleanup

### Full Cleanup (Recommended)

```bash
# Run from project root
./destroy-aws.sh
```

This will:
1. Remove the Docker stack
2. Destroy all AWS infrastructure
3. Clean up generated files

### Manual Cleanup

```bash
# 1. Remove stack
cd ansible/
ansible-playbook -i inventory/aws_hosts.yml destroy-stack.yml

# 2. Optionally remove volumes and secrets
ansible-playbook -i inventory/aws_hosts.yml destroy-stack.yml \
  -e remove_volumes=true \
  -e remove_secrets=true

# 3. Destroy infrastructure
cd ../terraform/
terraform destroy

# 4. Clean up inventory
rm ../ansible/inventory/aws_hosts.yml
```

## Troubleshooting

### SSH Connection Issues

```bash
# Verify key permissions
chmod 400 ~/.ssh/ca2-swarm-key.pem

# Test direct SSH
ssh -i ~/.ssh/ca2-swarm-key.pem ubuntu@<MANAGER_IP>

# Check security group allows SSH from your IP
aws ec2 describe-security-groups --group-names swarm-sg
```

### Terraform Issues

```bash
# Re-initialize
cd terraform/
terraform init -upgrade

# Check AWS credentials
aws sts get-caller-identity

# Validate configuration
terraform validate
```

### Ansible Issues

```bash
# Test connectivity
ansible all -i inventory/aws_hosts.yml -m ping

# Run with verbose output
ansible-playbook -i inventory/aws_hosts.yml swarm-setup.yml -vvv

# Check inventory
cat inventory/aws_hosts.yml
```

### Services Not Starting

```bash
# SSH to manager
ssh -i ~/.ssh/ca2-swarm-key.pem ubuntu@$MANAGER_IP

# Check service status
docker service ps metals-pipeline_producer --no-trunc

# View logs
docker service logs metals-pipeline_producer --tail 50

# Common issues:
# - Image not found: Push images to Docker Hub first
# - Resource constraints: Check node resources
# - Network issues: Verify security group rules
```

### Health Checks Failing

```bash
# Check if services are running
docker service ls

# Wait longer (services need time to start)
sleep 120

# Test from within swarm
docker exec $(docker ps -q -f name=producer | head -1) curl localhost:8000/health
```

## Cost Estimates

### Hourly Costs (us-east-2)
- 3 × t3.small instances: $0.0208/hour each = $0.0624/hour total
- Data transfer: Minimal for testing
- **Total**: ~$0.06-0.10/hour

### Assignment Duration
- Setup and testing: 2-4 hours
- **Estimated cost**: $0.25-0.50

### Cost Savings Tips
1. **Destroy when not in use**: Run `./destroy-aws.sh` when done testing
2. **Use t3.micro**: Change `instance_type` to `t3.micro` (free tier eligible)
3. **Same-day cleanup**: Costs are hourly, not daily

## Screenshots for Assignment

Capture these for your CA2 submission:

### 1. Infrastructure
```bash
# AWS Console showing 3 EC2 instances
# Or: terraform output
```

### 2. Swarm Cluster
```bash
ssh -i ~/.ssh/ca2-swarm-key.pem ubuntu@$MANAGER_IP
docker node ls
# Screenshot showing 3 nodes (1 manager, 2 workers)
```

### 3. Services Running
```bash
docker stack services metals-pipeline
# Screenshot showing all 5 services with replicas
```

### 4. Service Distribution
```bash
docker stack ps metals-pipeline
# Screenshot showing tasks distributed across nodes
```

### 5. Health Endpoints
```bash
curl http://$MANAGER_IP:8000/health | jq
curl http://$MANAGER_IP:8001/health | jq
# Screenshot showing healthy status
```

### 6. Scaling
```bash
docker service scale metals-pipeline_producer=5
docker service ps metals-pipeline_producer
# Screenshot showing 5 replicas
```

## Advantages Over Local Deployment

✅ **Meets CA2 Requirements**: True 3-node cluster  
✅ **Production-like**: Real distributed deployment  
✅ **Better Documentation**: Professional approach  
✅ **Portfolio Quality**: Shows cloud deployment skills  
✅ **Network Isolation**: Real overlay networks across nodes  

## Security Notes

### Current Setup (Development)
- SSH from anywhere (0.0.0.0/0)
- Health endpoints publicly accessible

### For Production
Update security groups:
```hcl
# Restrict SSH to your IP
cidr_blocks = ["YOUR_IP/32"]

# Use ALB for health endpoints
# Remove direct port exposure
```

## Next Steps After Deployment

1. ✅ Verify all 3 nodes in cluster
2. ✅ Test health endpoints
3. ✅ Run scaling demonstration
4. ✅ Capture screenshots
5. ✅ Test destroy/recreate cycle
6. ✅ Update README with AWS deployment option
7. ✅ Destroy infrastructure when done

---

**Note**: Remember to run `./destroy-aws.sh` when finished to avoid ongoing AWS charges!
