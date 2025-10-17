#!/bin/bash
# deploy.sh - Main deployment script

set -e

echo "=========================================="
echo "CA2 Metals Pipeline - Docker Swarm Deploy"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STACK_NAME="metals-pipeline"
REGISTRY="${REGISTRY:-yourusername}"

# Check if running on a swarm manager
if ! docker info | grep -q "Swarm: active"; then
    echo -e "${RED}Error: Docker Swarm is not initialized${NC}"
    echo "Run './scripts/init-swarm.sh' first"
    exit 1
fi

if ! docker node ls >/dev/null 2>&1; then
    echo -e "${RED}Error: Not running on a swarm manager node${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Docker Swarm is active${NC}"
echo ""

# Check if secrets exist
echo "Checking Docker secrets..."
SECRETS_EXIST=true

if ! docker secret inspect mongodb-password >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Secret 'mongodb-password' not found${NC}"
    SECRETS_EXIST=false
fi

if ! docker secret inspect kafka-password >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Secret 'kafka-password' not found${NC}"
    SECRETS_EXIST=false
fi

if ! docker secret inspect api-key >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Secret 'api-key' not found${NC}"
    SECRETS_EXIST=false
fi

if [ "$SECRETS_EXIST" = false ]; then
    echo ""
    echo "Creating secrets..."
    echo "SecureMongoP@ss123" | docker secret create mongodb-password -
    echo "KafkaAdm1nP@ss456" | docker secret create kafka-password -
    echo "metals-api-key-placeholder" | docker secret create api-key -
    echo -e "${GREEN}✓ Secrets created${NC}"
fi

echo -e "${GREEN}✓ All secrets exist${NC}"
echo ""

# Check if images exist
echo "Checking container images..."
if ! docker image inspect ${REGISTRY}/metals-producer:v1.0 >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Producer image not found. Run './scripts/build-images.sh' first${NC}"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

if ! docker image inspect ${REGISTRY}/metals-processor:v1.0 >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Processor image not found. Run './scripts/build-images.sh' first${NC}"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""

# Deploy stack
echo "Deploying stack '${STACK_NAME}'..."
REGISTRY=${REGISTRY} docker stack deploy -c docker-compose.yml ${STACK_NAME}

echo ""
echo -e "${GREEN}✓ Stack deployment initiated${NC}"
echo ""

# Wait for services to start
echo "Waiting for services to start..."
sleep 10

# Show deployment status
echo ""
echo "Service Status:"
docker stack services ${STACK_NAME}

echo ""
echo "Task Status:"
docker stack ps ${STACK_NAME} --no-trunc

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Wait for all services to be ready (2-3 minutes)"
echo "  2. Run: ./scripts/validate-stack.sh"
echo "  3. Run: ./scripts/smoke-test.sh"
echo ""
echo "To view logs:"
echo "  docker service logs -f ${STACK_NAME}_producer"
echo "  docker service logs -f ${STACK_NAME}_processor"
echo ""
echo "To scale services:"
echo "  docker service scale ${STACK_NAME}_producer=5"
echo ""

# ===================================================
# destroy.sh - Cleanup script
# ===================================================
#!/bin/bash

set -e

echo "=========================================="
echo "CA2 Metals Pipeline - Cleanup"
echo "=========================================="
echo ""

STACK_NAME="metals-pipeline"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Confirm destruction
echo -e "${YELLOW}WARNING: This will remove the entire stack and all data${NC}"
read -p "Are you sure you want to continue? (yes/NO) " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Cancelled"
    exit 0
fi

echo "Removing stack '${STACK_NAME}'..."
docker stack rm ${STACK_NAME}

echo ""
echo "Waiting for services to shut down..."
sleep 10

# Wait for all containers to stop
while docker ps | grep -q ${STACK_NAME}; do
    echo "Waiting for containers to stop..."
    sleep 5
done

echo -e "${GREEN}✓ All containers stopped${NC}"

# Remove volumes (optional)
read -p "Remove persistent volumes? This will DELETE ALL DATA (yes/NO) " -r
echo

if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Removing volumes..."
    docker volume ls | grep ${STACK_NAME} | awk '{print $2}' | xargs -r docker volume rm
    echo -e "${GREEN}✓ Volumes removed${NC}"
fi

# Remove secrets (optional)
read -p "Remove secrets? (yes/NO) " -r
echo

if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Removing secrets..."
    docker secret rm mongodb-password kafka-password api-key 2>/dev/null || true
    echo -e "${GREEN}✓ Secrets removed${NC}"
fi

# Remove networks
echo "Cleaning up networks..."
docker network ls | grep ${STACK_NAME} | awk '{print $2}' | xargs -r docker network rm 2>/dev/null || true

echo ""
echo -e "${GREEN}=========================================="
echo "Cleanup Complete!"
echo "==========================================${NC}"

# ===================================================
# scripts/init-swarm.sh - Initialize Docker Swarm
# ===================================================
#!/bin/bash

set -e

echo "=========================================="
echo "Initializing Docker Swarm"
echo "=========================================="
echo ""

# Check if already in swarm
if docker info | grep -q "Swarm: active"; then
    echo "Docker Swarm is already initialized"
    echo ""
    docker node ls
    echo ""
    echo "Manager Join Token:"
    docker swarm join-token manager
    echo ""
    echo "Worker Join Token:"
    docker swarm join-token worker
    exit 0
fi

# Get primary IP address
IP_ADDR=$(hostname -I | awk '{print $1}')
echo "Detected IP Address: $IP_ADDR"
echo ""

# Initialize swarm
echo "Initializing swarm..."
docker swarm init --advertise-addr $IP_ADDR

echo ""
echo "✓ Swarm initialized successfully!"
echo ""

# Show node status
docker node ls

echo ""
echo "To add worker nodes, run the following on each worker:"
echo ""
docker swarm join-token worker

echo ""
echo "To add manager nodes, run the following on each manager:"
echo ""
docker swarm join-token manager

# ===================================================
# scripts/build-images.sh - Build and push images
# ===================================================
#!/bin/bash

set -e

echo "=========================================="
echo "Building Container Images"
echo "=========================================="
echo ""

REGISTRY="${REGISTRY:-yourusername}"
VERSION="v1.0"

# Check if logged into registry
if ! docker info | grep -q "Username"; then
    echo "Warning: Not logged into Docker registry"
    read -p "Login now? (y/N) " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker login
    fi
fi

# Build producer
echo "Building producer image..."
cd producer/
docker build -t ${REGISTRY}/metals-producer:${VERSION} .
docker tag ${REGISTRY}/metals-producer:${VERSION} ${REGISTRY}/metals-producer:latest
cd ..

echo "✓ Producer image built"
echo ""

# Build processor
echo "Building processor image..."
cd processor/
docker build -t ${REGISTRY}/metals-processor:${VERSION} .
docker tag ${REGISTRY}/metals-processor:${VERSION} ${REGISTRY}/metals-processor:latest
cd ..

echo "✓ Processor image built"
echo ""

# Push images
read -p "Push images to registry? (y/N) " -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Pushing producer image..."
    docker push ${REGISTRY}/metals-producer:${VERSION}
    docker push ${REGISTRY}/metals-producer:latest
    
    echo "Pushing processor image..."
    docker push ${REGISTRY}/metals-processor:${VERSION}
    docker push ${REGISTRY}/metals-processor:latest
    
    echo "✓ Images pushed to registry"
fi

echo ""
echo "=========================================="
echo "Build Complete!"
echo "=========================================="
echo ""
echo "Images built:"
echo "  ${REGISTRY}/metals-producer:${VERSION}"
echo "  ${REGISTRY}/metals-processor:${VERSION}"

# ===================================================
# scripts/validate-stack.sh - Validate deployment
# ===================================================
#!/bin/bash

set -e

STACK_NAME="metals-pipeline"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Validating Stack Deployment"
echo "=========================================="
echo ""

# Check if stack exists
if ! docker stack ls | grep -q ${STACK_NAME}; then
    echo -e "${RED}✗ Stack '${STACK_NAME}' not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Stack exists${NC}"

# Check services
echo ""
echo "Service Status:"
SERVICES=$(docker stack services ${STACK_NAME} --format "{{.Name}}" | wc -l)
EXPECTED_SERVICES=5

if [ "$SERVICES" -ne "$EXPECTED_SERVICES" ]; then
    echo -e "${RED}✗ Expected ${EXPECTED_SERVICES} services, found ${SERVICES}${NC}"
    docker stack services ${STACK_NAME}
    exit 1
fi

echo -e "${GREEN}✓ All ${SERVICES} services found${NC}"
docker stack services ${STACK_NAME}

# Check replicas
echo ""
echo "Checking service replicas..."
READY=true

for service in zookeeper kafka mongodb processor producer; do
    REPLICAS=$(docker service ls --filter name=${STACK_NAME}_${service} --format "{{.Replicas}}")
    if [[ ! $REPLICAS =~ ^[1-9]/[1-9] ]]; then
        echo -e "${YELLOW}⚠ ${service}: ${REPLICAS}${NC}"
        READY=false
    else
        echo -e "${GREEN}✓ ${service}: ${REPLICAS}${NC}"
    fi
done

if [ "$READY" = false ]; then
    echo ""
    echo -e "${YELLOW}Some services are not ready yet. Wait a moment and try again.${NC}"
    exit 1
fi

# Check networks
echo ""
echo "Checking networks..."
NETWORKS=$(docker network ls | grep ${STACK_NAME} | wc -l)
if [ "$NETWORKS" -lt 3 ]; then
    echo -e "${RED}✗ Expected at least 3 networks, found ${NETWORKS}${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Networks configured${NC}"

# Check volumes
echo ""
echo "Checking volumes..."
VOLUMES=$(docker volume ls | grep ${STACK_NAME} | wc -l)
if [ "$VOLUMES" -lt 4 ]; then
    echo -e "${YELLOW}⚠ Expected at least 4 volumes, found ${VOLUMES}${NC}"
fi

echo -e "${GREEN}✓ Volumes created${NC}"

# Check secrets
echo ""
echo "Checking secrets..."
for secret in mongodb-password kafka-password api-key; do
    if docker secret inspect $secret >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Secret '${secret}' exists${NC}"
    else
        echo -e "${RED}✗ Secret '${secret}' not found${NC}"
        READY=false
    fi
done

echo ""
echo "=========================================="
if [ "$READY" = true ]; then
    echo -e "${GREEN}✓ Stack validation passed!${NC}"
    echo "=========================================="
    echo ""
    echo "Next step: Run ./scripts/smoke-test.sh"
    exit 0
else
    echo -e "${RED}✗ Stack validation failed${NC}"
    echo "=========================================="
    exit 1
fi