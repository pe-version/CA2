.PHONY: help init build deploy status smoke-test scaling-test logs destroy validate scale-up scale-down

STACK_NAME := metals-pipeline
REGISTRY := ${REGISTRY}

help:
	@echo "CA2 Metals Pipeline - Docker Swarm Commands"
	@echo ""
	@echo "Setup:"
	@echo "  make init           - Initialize Docker Swarm"
	@echo "  make build          - Build and push images"
	@echo "  make deploy         - Deploy the stack"
	@echo ""
	@echo "Testing:"
	@echo "  make validate       - Validate deployment"
	@echo "  make smoke-test     - Run smoke tests"
	@echo "  make scaling-test   - Run scaling demo"
	@echo "  make health         - Check health endpoints"
	@echo ""
	@echo "Monitoring:"
	@echo "  make status         - Show service status"
	@echo "  make logs           - View all logs"
	@echo "  make logs-producer  - View producer logs"
	@echo "  make logs-processor - View processor logs"
	@echo ""
	@echo "Scaling:"
	@echo "  make scale-up       - Scale producers to 5"
	@echo "  make scale-down     - Scale back to 1"
	@echo ""
	@echo "Cleanup:"
	@echo "  make destroy        - Remove stack"
	@echo "  make clean-all      - Remove everything"
	@echo ""

check-swarm:
	@if ! docker info | grep -q "Swarm: active"; then \
		echo "Error: Docker Swarm not initialized"; \
		echo "Run 'make init' first"; \
		exit 1; \
	fi

init:
	@echo "Initializing Docker Swarm..."
	@./scripts/init-swarm.sh

build:
	@echo "Building images..."
	@./scripts/build-images.sh

create-secrets:
	@echo "Creating secrets..."
	@if ! docker secret inspect mongodb-password >/dev/null 2>&1; then \
		echo "SecureMongoP@ss123" | docker secret create mongodb-password -; \
	fi
	@if ! docker secret inspect kafka-password >/dev/null 2>&1; then \
		echo "KafkaAdm1nP@ss456" | docker secret create kafka-password -; \
	fi
	@if ! docker secret inspect api-key >/dev/null 2>&1; then \
		echo "metals-api-key-placeholder" | docker secret create api-key -; \
	fi

deploy: check-swarm create-secrets
	@echo "Deploying $(STACK_NAME)..."
	@./deploy.sh

validate: check-swarm
	@./scripts/validate-stack.sh

status: check-swarm
	@docker stack services $(STACK_NAME)
	@echo ""
	@docker stack ps $(STACK_NAME)

smoke-test: check-swarm
	@./scripts/smoke-test.sh

scaling-test: check-swarm
	@./scripts/scaling-test.sh

logs: check-swarm
	@docker service logs -f $(STACK_NAME)_producer

logs-producer: check-swarm
	@docker service logs -f $(STACK_NAME)_producer

logs-processor: check-swarm
	@docker service logs -f $(STACK_NAME)_processor

logs-kafka: check-swarm
	@docker service logs -f $(STACK_NAME)_kafka

logs-mongodb: check-swarm
	@docker service logs -f $(STACK_NAME)_mongodb

health:
	@echo "Producer Health:"
	@curl -s http://localhost:8000/health | jq '.' || echo "Not available"
	@echo ""
	@echo "Processor Health:"
	@curl -s http://localhost:8001/health | jq '.' || echo "Not available"

scale-up: check-swarm
	@echo "Scaling producers to 5..."
	@docker service scale $(STACK_NAME)_producer=5
	@sleep 10
	@docker service ls --filter name=$(STACK_NAME)

scale-down: check-swarm
	@echo "Scaling back to 1..."
	@docker service scale $(STACK_NAME)_producer=1
	@docker service scale $(STACK_NAME)_processor=1

destroy: check-swarm
	@./destroy.sh

clean-all: destroy
	@echo "Cleaning volumes..."
	@docker volume ls | grep $(STACK_NAME) | awk '{print $$2}' | xargs -r docker volume rm || true
	@echo "Removing secrets..."
	@docker secret rm mongodb-password kafka-password api-key 2>/dev/null || true

quickstart: init build deploy
	@echo "Waiting for services..."
	@sleep 60
	@make validate
	@make smoke-test
