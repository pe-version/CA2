#!/bin/bash
set -e

echo "=========================================="
echo "CA2 Metals Pipeline - Docker Swarm Deploy"
echo "=========================================="
echo ""

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

STACK_NAME="metals-pipeline"
REGISTRY="${REGISTRY:-hiphophippo}"

# Check swarm
if ! docker info | grep -q "Swarm: active"; then
    echo -e "${RED}Error: Docker Swarm not initialized${NC}"
    echo "Run './scripts/init-swarm.sh' first"
    exit 1
fi

if ! docker node ls >/dev/null 2>&1; then
    echo -e "${RED}Error: Not on swarm manager node${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Docker Swarm active${NC}"

# Check secrets
echo "Checking secrets..."
for secret in mongodb-password kafka-password api-key; do
    if ! docker secret inspect $secret >/dev/null 2>&1; then
        echo -e "${YELLOW}Creating secret: $secret${NC}"
        case $secret in
            mongodb-password)
                echo "SecureMongoP@ss123" | docker secret create $secret -
                ;;
            kafka-password)
                echo "KafkaAdm1nP@ss456" | docker secret create $secret -
                ;;
            api-key)
                echo "metals-api-key-placeholder" | docker secret create $secret -
                ;;
        esac
    fi
done

echo -e "${GREEN}✓ Secrets ready${NC}"
echo ""

# Deploy stack
echo "Deploying stack..."
REGISTRY=${REGISTRY} docker stack deploy -c docker-compose.yml ${STACK_NAME}

echo ""
echo -e "${GREEN}✓ Deployment initiated${NC}"
echo ""
echo "Service Status:"
docker stack services ${STACK_NAME}

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Wait 2-3 minutes for services to start"
echo "  2. Run: make validate"
echo "  3. Run: make smoke-test"
echo ""
echo "View logs: make logs-producer"
echo "Scale: make scale-up"
echo ""
