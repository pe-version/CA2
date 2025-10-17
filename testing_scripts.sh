#!/bin/bash
# scripts/smoke-test.sh - End-to-end smoke test

set -e

STACK_NAME="metals-pipeline"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "CA2 Metals Pipeline - Smoke Test"
echo "=========================================="
echo ""

# Find manager node IP for health checks
MANAGER_IP=$(docker node inspect self --format '{{.Status.Addr}}')

echo -e "${BLUE}Testing infrastructure...${NC}"
echo ""

# Test 1: Check if services are running
echo "1. Checking service status..."
if docker stack services ${STACK_NAME} | grep -q "0/"; then
    echo -e "${RED}✗ Some services have 0 replicas${NC}"
    docker stack services ${STACK_NAME}
    exit 1
fi
echo -e "${GREEN}✓ All services have active replicas${NC}"
echo ""

# Test 2: Producer health check
echo "2. Testing Producer health endpoint..."
sleep 5

MAX_RETRIES=30
RETRY_COUNT=0
PRODUCER_HEALTHY=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
        PRODUCER_RESPONSE=$(curl -s http://localhost:8000/health)
        KAFKA_CONNECTED=$(echo $PRODUCER_RESPONSE | grep -o '"kafka_connected":[^,}]*' | cut -d':' -f2)
        
        if [ "$KAFKA_CONNECTED" = "true" ]; then
            PRODUCER_HEALTHY=true
            echo -e "${GREEN}✓ Producer is healthy and connected to Kafka${NC}"
            break
        fi
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo -e "${YELLOW}⏳ Waiting for producer... (${RETRY_COUNT}/${MAX_RETRIES})${NC}"
    sleep 5
done

if [ "$PRODUCER_HEALTHY" = false ]; then
    echo -e "${RED}✗ Producer health check failed${NC}"
    echo "Producer logs:"
    docker service logs ${STACK_NAME}_producer --tail 20
    exit 1
fi
echo ""

# Test 3: Processor health check
echo "3. Testing Processor health endpoint..."
RETRY_COUNT=0
PROCESSOR_HEALTHY=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -sf http://localhost:8001/health > /dev/null 2>&1; then
        PROCESSOR_RESPONSE=$(curl -s http://localhost:8001/health)
        KAFKA_CONNECTED=$(echo $PROCESSOR_RESPONSE | grep -o '"kafka_connected":[^,}]*' | cut -d':' -f2)
        MONGODB_STATUS=$(echo $PROCESSOR_RESPONSE | grep -o '"mongodb_status":"[^"]*"' | cut -d'"' -f4)
        
        if [ "$KAFKA_CONNECTED" = "true" ] && [ "$MONGODB_STATUS" = "connected" ]; then
            PROCESSOR_HEALTHY=true
            echo -e "${GREEN}✓ Processor is healthy and connected to Kafka and MongoDB${NC}"
            break
        fi
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo -e "${YELLOW}⏳ Waiting for processor... (${RETRY_COUNT}/${MAX_RETRIES})${NC}"
    sleep 5
done

if [ "$PROCESSOR_HEALTHY" = false ]; then
    echo -e "${RED}✗ Processor health check failed${NC}"
    echo "Processor logs:"
    docker service logs ${STACK_NAME}_processor --tail 20
    exit 1
fi
echo ""

# Test 4: Send test message
echo "4. Sending test message..."
TEST_RESPONSE=$(curl -s -X POST http://localhost:8000/produce \
    -H "Content-Type: application/json" \
    -d '{}' 2>&1)

if echo "$TEST_RESPONSE" | grep -q '"success":true'; then
    echo -e "${GREEN}✓ Test message sent successfully${NC}"
    EVENT_ID=$(echo "$TEST_RESPONSE" | grep -o '"event_id":"[^"]*"' | cut -d'"' -f4)
    echo "  Event ID: $EVENT_ID"
else
    echo -e "${RED}✗ Failed to send test message${NC}"
    echo "$TEST_RESPONSE"
    exit 1
fi
echo ""

# Test 5: Verify Kafka topic
echo "5. Verifying Kafka topic..."
KAFKA_CONTAINER=$(docker ps -q -f name=${STACK_NAME}_kafka)

if [ -z "$KAFKA_CONTAINER" ]; then
    echo -e "${RED}✗ Kafka container not found${NC}"
    exit 1
fi

# Check topic exists
if docker exec $KAFKA_CONTAINER kafka-topics \
    --bootstrap-server localhost:9092 \
    --list | grep -q "metals-prices"; then
    echo -e "${GREEN}✓ Kafka topic 'metals-prices' exists${NC}"
else
    echo -e "${RED}✗ Kafka topic 'metals-prices' not found${NC}"
    exit 1
fi

# Check for messages
TOPIC_INFO=$(docker exec $KAFKA_CONTAINER kafka-topics \
    --bootstrap-server localhost:9092 \
    --describe --topic metals-prices)

echo "  Topic info: $TOPIC_INFO"
echo ""

# Test 6: Wait and verify MongoDB
echo "6. Verifying data in MongoDB..."
echo "  Waiting 30 seconds for message processing..."
sleep 30

MONGODB_CONTAINER=$(docker ps -q -f name=${STACK_NAME}_mongodb)

if [ -z "$MONGODB_CONTAINER" ]; then
    echo -e "${RED}✗ MongoDB container not found${NC}"
    exit 1
fi

# Get MongoDB password from secret
MONGODB_PASSWORD=$(docker secret inspect mongodb-password --format '{{.Spec.Data}}' | base64 -d)

# Count documents
DOC_COUNT=$(docker exec $MONGODB_CONTAINER mongosh -u admin -p "$MONGODB_PASSWORD" \
    --authenticationDatabase admin metals \
    --eval "db.prices.countDocuments({})" --quiet 2>/dev/null | tail -1)

if [ "$DOC_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ MongoDB contains ${DOC_COUNT} processed documents${NC}"
    
    # Show sample document
    echo ""
    echo "Sample document:"
    docker exec $MONGODB_CONTAINER mongosh -u admin -p "$MONGODB_PASSWORD" \
        --authenticationDatabase admin metals \
        --eval "db.prices.findOne()" --quiet 2>/dev/null | head -20
else
    echo -e "${YELLOW}⚠ Mong