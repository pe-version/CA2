.PHONY: help init build deploy destroy validate smoke-test scaling-test logs \
        deploy-aws destroy-aws validate-aws ssh-manager \
        clean-all status health scale-up scale-down

# ============================================
# CA2 Metals Pipeline - Makefile
# Supports both Local and AWS deployments
# ============================================

STACK_NAME := metals-pipeline
REGISTRY ?= hiphophippo
AWS_REGION := us-east-2

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m

# ============================================
# Help
# ============================================

help:
	@echo "=========================================="
	@echo "CA2 Metals Pipeline - Available Commands"
	@echo "=========================================="
	@echo ""
	@echo "$(BLUE)AWS Deployment (Recommended - 3-Node Cluster):$(NC)"
	@echo "  make deploy-aws      - Deploy to AWS (Terraform + Ansible)"
	@echo "  make validate-aws    - Validate AWS deployment"
	@echo "  make ssh-manager     - SSH to AWS manager node"
	@echo "  make destroy-aws     - Destroy AWS infrastructure"
	@echo ""
	@echo "$(BLUE)Local Deployment (Development/Testing):$(NC)"
	@echo "  make init            - Initialize local Docker Swarm"
	@echo "  make build           - Build and push images"
	@echo "  make deploy          - Deploy locally"
	@echo "  make validate        - Validate local deployment"
	@echo "  make destroy         - Destroy local deployment"
	@echo ""
	@echo "$(BLUE)Testing & Monitoring (Both):$(NC)"
	@echo "  make smoke-test      - Run smoke tests"
	@echo "  make scaling-test    - Run scaling demonstration"
	@echo "  make health          - Check health endpoints"
	@echo "  make status          - Show service status"
	@echo "  make logs            - View service logs"
	@echo ""
	@echo "$(BLUE)Scaling (Both):$(NC)"
	@echo "  make scale-up        - Scale producers to 5"
	@echo "  make scale-down      - Scale back to 1"
	@echo ""
	@echo "$(BLUE)Cleanup:$(NC)"
	@echo "  make clean-all       - Remove everything (local or AWS)"
	@echo ""
	@echo "$(YELLOW)Quick Start:$(NC)"
	@echo "  make deploy-aws      # For assignment submission"
	@echo "  make deploy          # For local testing"
	@echo ""

# ============================================
# AWS Deployment (Primary - 3-Node Cluster)
# ============================================

deploy-aws:
	@echo "$(BLUE)Deploying to AWS (3-node cluster)...$(NC)"
	@./deploy-aws.sh
	@echo ""
	@echo "$(GREEN)✓ AWS deployment complete$(NC)"
	@echo "Run 'make validate-aws' to verify"

validate-aws:
	@echo "$(BLUE)Validating AWS deployment...$(NC)"
	@cd terraform && \
	MANAGER_IP=$$(terraform output -raw manager_public_ip) && \
	echo "" && \
	echo "Testing health endpoints..." && \
	echo "Producer:" && \
	curl -sf http://$$MANAGER_IP:8000/health | jq '.' || echo "Not ready yet" && \
	echo "" && \
	echo "Processor:" && \
	curl -sf http://$$MANAGER_IP:8001/health | jq '.' || echo "Not ready yet" && \
	echo "" && \
	echo "To check detailed status:" && \
	echo "  make ssh-manager" && \
	echo "  docker stack ps $(STACK_NAME)"

ssh-manager:
	@cd terraform && \
	MANAGER_IP=$$(terraform output -raw manager_public_ip) && \
	echo "Connecting to AWS manager node..." && \
	ssh -i ~/.ssh/$$(terraform output -json ssh_connection_strings | jq -r '.manager' | grep -o '[^/]*\.pem' | sed 's/\.pem//') ubuntu@$$MANAGER_IP

destroy-aws:
	@echo "$(YELLOW)Destroying AWS infrastructure...$(NC)"
	@./destroy-aws.sh
	@echo "$(GREEN)✓ AWS cleanup complete$(NC)"

terraform-plan:
	@echo "$(BLUE)Planning Terraform changes...$(NC)"
	@cd terraform && terraform plan

terraform-output:
	@cd terraform && terraform output

# ============================================
# Local Deployment (Development)
# ============================================

check-swarm:
	@if ! docker info | grep -q "Swarm: active"; then \
		echo "$(YELLOW)Docker Swarm not initialized$(NC)"; \
		echo "Run 'make init' first"; \
		exit 1; \
	fi

init:
	@echo "$(BLUE)Initializing local Docker Swarm...$(NC)"
	@./scripts/init-swarm.sh
	@echo "$(GREEN)✓ Swarm initialized$(NC)"

build:
	@echo "$(BLUE)Building container images...$(NC)"
	@cd producer && docker build -t ${REGISTRY}/metals-producer:v1.0 .
	@cd processor && docker build -t ${REGISTRY}/metals-processor:v1.0 .
	@echo "$(BLUE)Pushing to registry...$(NC)"
	@docker push ${REGISTRY}/metals-producer:v1.0
	@docker push ${REGISTRY}/metals-processor:v1.0
	@echo "$(GREEN)✓ Images built and pushed$(NC)"

create-secrets:
	@echo "Creating Docker secrets..."
	@if ! docker secret inspect mongodb-password >/dev/null 2>&1; then \
		echo "SecureMongoP@ss123" | docker secret create mongodb-password -; \
	fi
	@if ! docker secret inspect kafka-password >/dev/null 2>&1; then \
		echo "KafkaAdm1nP@ss456" | docker secret create kafka-password -; \
	fi
	@if ! docker secret inspect api-key >/dev/null 2>&1; then \
		echo "metals-api-key-placeholder" | docker secret create api-key -; \
	fi
	@echo "$(GREEN)✓ Secrets ready$(NC)"

deploy: check-swarm create-secrets
	@echo "$(BLUE)Deploying to local Docker Swarm...$(NC)"
	@./deploy.sh
	@echo "$(GREEN)✓ Local deployment complete$(NC)"
	@echo "Run 'make validate' to verify"

validate: check-swarm
	@echo "$(BLUE)Validating local deployment...$(NC)"
	@./scripts/validate-stack.sh

destroy: check-swarm
	@echo "$(YELLOW)Destroying local deployment...$(NC)"
	@./destroy.sh
	@echo "$(GREEN)✓ Local cleanup complete$(NC)"

# ============================================
# Testing & Validation (Works for Both)
# ============================================

smoke-test:
	@echo "$(BLUE)Running smoke tests...$(NC)"
	@./scripts/smoke-test.sh

scaling-test:
	@echo "$(BLUE)Running scaling demonstration...$(NC)"
	@./scripts/scaling-test.sh

health:
	@echo "$(BLUE)Checking health endpoints...$(NC)"
	@echo ""
	@echo "Producer Health:"
	@curl -sf http://localhost:8000/health | jq '.' 2>/dev/null || echo "Not available (try AWS deployment)"
	@echo ""
	@echo "Processor Health:"
	@curl -sf http://localhost:8001/health | jq '.' 2>/dev/null || echo "Not available (try AWS deployment)"
	@echo ""

health-aws:
	@cd terraform && \
	MANAGER_IP=$$(terraform output -raw manager_public_ip 2>/dev/null) && \
	if [ -n "$$MANAGER_IP" ]; then \
		echo "$(BLUE)AWS Health Endpoints:$(NC)"; \
		echo ""; \
		echo "Producer:"; \
		curl -sf http://$$MANAGER_IP:8000/health | jq '.'; \
		echo ""; \
		echo "Processor:"; \
		curl -sf http://$$MANAGER_IP:8001/health | jq '.'; \
	else \
		echo "AWS infrastructure not deployed"; \
	fi

# ============================================
# Monitoring (Works for Both)
# ============================================

status:
	@if docker info | grep -q "Swarm: active"; then \
		echo "$(BLUE)Service Status:$(NC)"; \
		docker stack services $(STACK_NAME) 2>/dev/null || echo "Stack not deployed"; \
		echo ""; \
		echo "$(BLUE)Task Status:$(NC)"; \
		docker stack ps $(STACK_NAME) 2>/dev/null || echo "Stack not deployed"; \
	else \
		echo "Docker Swarm not initialized"; \
	fi

logs:
	@docker service logs -f $(STACK_NAME)_producer 2>/dev/null || echo "Service not found"

logs-producer:
	@docker service logs -f $(STACK_NAME)_producer

logs-processor:
	@docker service logs -f $(STACK_NAME)_processor

logs-kafka:
	@docker service logs -f $(STACK_NAME)_kafka

logs-mongodb:
	@docker service logs -f $(STACK_NAME)_mongodb

logs-all:
	@echo "$(BLUE)Tailing all service logs (Ctrl+C to stop)...$(NC)"
	@docker service logs -f $(STACK_NAME)_producer &
	@docker service logs -f $(STACK_NAME)_processor &
	@docker service logs -f $(STACK_NAME)_kafka &
	@wait

# ============================================
# Scaling (Works for Both)
# ============================================

scale-up:
	@echo "$(BLUE)Scaling producers to 5 replicas...$(NC)"
	@docker service scale $(STACK_NAME)_producer=5
	@sleep 10
	@docker service ls --filter name=$(STACK_NAME)_producer
	@echo "$(GREEN)✓ Scaled to 5 producers$(NC)"

scale-down:
	@echo "$(BLUE)Scaling back to baseline...$(NC)"
	@docker service scale $(STACK_NAME)_producer=1
	@docker service scale $(STACK_NAME)_processor=1
	@echo "$(GREEN)✓ Scaled to baseline$(NC)"

scale:
	@echo "Custom scaling:"
	@read -p "Service (producer/processor): " service; \
	read -p "Replicas (1-10): " replicas; \
	docker service scale $(STACK_NAME)_$$service=$$replicas; \
	echo "$(GREEN)✓ Scaled $$service to $$replicas$(NC)"

# ============================================
# Cleanup
# ============================================

clean-all:
	@echo "$(YELLOW)Complete cleanup...$(NC)"
	@if [ -d "terraform" ] && [ -f "terraform/terraform.tfstate" ]; then \
		echo "Detected AWS deployment..."; \
		$(MAKE) destroy-aws; \
	elif docker info | grep -q "Swarm: active"; then \
		echo "Detected local deployment..."; \
		$(MAKE) destroy; \
		echo "Removing volumes..."; \
		docker volume ls | grep $(STACK_NAME) | awk '{print $$2}' | xargs -r docker volume rm || true; \
		echo "Removing secrets..."; \
		docker secret rm mongodb-password kafka-password api-key 2>/dev/null || true; \
	else \
		echo "No deployment found"; \
	fi
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

# ============================================
# Advanced Operations
# ============================================

inspect-service:
	@read -p "Service name (producer/processor/kafka/mongodb): " service; \
	docker service inspect $(STACK_NAME)_$$service --pretty

inspect-networks:
	@echo "$(BLUE)Network Details:$(NC)"
	@docker network ls | grep $(STACK_NAME)
	@echo ""
	@docker network inspect $(STACK_NAME)_metals-frontend 2>/dev/null || echo "Network not found"

inspect-volumes:
	@echo "$(BLUE)Volume Details:$(NC)"
	@docker volume ls | grep $(STACK_NAME)

nodes:
	@echo "$(BLUE)Swarm Nodes:$(NC)"
	@docker node ls 2>/dev/null || echo "Not in swarm mode"

stats:
	@echo "$(BLUE)Resource Usage:$(NC)"
	@docker stats --no-stream $$(docker ps -q -f name=$(STACK_NAME)) 2>/dev/null || echo "No containers running"

# ============================================
# Quick Commands
# ============================================

quick-aws: deploy-aws validate-aws
	@echo "$(GREEN)AWS deployment validated!$(NC)"

quick-local: init build deploy validate
	@echo "$(GREEN)Local deployment validated!$(NC)"

full-test: smoke-test scaling-test
	@echo "$(GREEN)All tests passed!$(NC)"

# ============================================
# Debug Commands
# ============================================

debug-producer:
	@echo "$(BLUE)Producer Debug Info:$(NC)"
	@docker service ps $(STACK_NAME)_producer --no-trunc
	@echo ""
	@docker service logs $(STACK_NAME)_producer --tail 50

debug-processor:
	@echo "$(BLUE)Processor Debug Info:$(NC)"
	@docker service ps $(STACK_NAME)_processor --no-trunc
	@echo ""
	@docker service logs $(STACK_NAME)_processor --tail 50

debug-all:
	@echo "$(BLUE)Complete Debug Info:$(NC)"
	@echo ""
	@echo "=== Nodes ==="
	@docker node ls 2>/dev/null || echo "Not in swarm"
	@echo ""
	@echo "=== Services ==="
	@docker service ls --filter name=$(STACK_NAME)
	@echo ""
	@echo "=== Tasks ==="
	@docker stack ps $(STACK_NAME) --no-trunc 2>/dev/null || echo "Stack not deployed"
	@echo ""
	@echo "=== Networks ==="
	@docker network ls | grep $(STACK_NAME)
	@echo ""
	@echo "=== Volumes ==="
	@docker volume ls | grep $(STACK_NAME)

# ============================================
# CI/CD Helpers
# ============================================

validate-manifests:
	@echo "$(BLUE)Validating manifests...$(NC)"
	@docker-compose -f docker-compose.yml config >/dev/null
	@echo "$(GREEN)✓ docker-compose.yml valid$(NC)"

lint-terraform:
	@if [ -d "terraform" ]; then \
		echo "$(BLUE)Linting Terraform...$(NC)"; \
		cd terraform && terraform fmt -check; \
		cd terraform && terraform validate; \
		echo "$(GREEN)✓ Terraform valid$(NC)"; \
	fi

lint-ansible:
	@if [ -d "ansible" ]; then \
		echo "$(BLUE)Linting Ansible...$(NC)"; \
		ansible-lint ansible/*.yml 2>/dev/null || echo "ansible-lint not installed"; \
	fi

# ============================================
# Documentation
# ============================================

show-urls:
	@echo "$(BLUE)Access URLs:$(NC)"
	@echo ""
	@echo "Local:"
	@echo "  Producer:  http://localhost:8000/health"
	@echo "  Processor: http://localhost:8001/health"
	@echo ""
	@if [ -d "terraform" ]; then \
		cd terraform && \
		MANAGER_IP=$$(terraform output -raw manager_public_ip 2>/dev/null) && \
		if [ -n "$$MANAGER_IP" ]; then \
			echo "AWS:"; \
			echo "  Producer:  http://$$MANAGER_IP:8000/health"; \
			echo "  Processor: http://$$MANAGER_IP:8001/health"; \
		fi; \
	fi

show-config:
	@echo "$(BLUE)Current Configuration:$(NC)"
	@echo "Stack Name: $(STACK_NAME)"
	@echo "Registry: $(REGISTRY)"
	@echo "AWS Region: $(AWS_REGION)"
	@echo ""
	@echo "Deployment Type:"
	@if [ -f "terraform/terraform.tfstate" ]; then \
		echo "  ✓ AWS (3-node cluster)"; \
	elif docker info | grep -q "Swarm: active"; then \
		echo "  ✓ Local (Docker Swarm)"; \
	else \
		echo "  ✗ Not deployed"; \
	fi