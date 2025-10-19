#!/bin/bash
set -e

echo "=========================================="
echo "CA2 Metals Pipeline - Cleanup"
echo "=========================================="
echo ""

STACK_NAME="metals-pipeline"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}WARNING: This will remove the entire stack${NC}"
read -p "Continue? (yes/NO) " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Cancelled"
    exit 0
fi

echo "Removing stack..."
docker stack rm ${STACK_NAME}

echo "Waiting for shutdown..."
sleep 10

while docker ps | grep -q ${STACK_NAME}; do
    echo "Waiting for containers..."
    sleep 5
done

echo -e "${GREEN}✓ Stack removed${NC}"

read -p "Remove volumes? This will DELETE ALL DATA (yes/NO) " -r
echo

if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    docker volume ls | grep ${STACK_NAME} | awk '{print $2}' | xargs -r docker volume rm
    echo -e "${GREEN}✓ Volumes removed${NC}"
fi

read -p "Remove secrets? (yes/NO) " -r
echo

if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    docker secret rm mongodb-password kafka-password api-key 2>/dev/null || true
    echo -e "${GREEN}✓ Secrets removed${NC}"
fi

echo ""
echo -e "${GREEN}Cleanup complete${NC}"
