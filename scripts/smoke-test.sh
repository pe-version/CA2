set -e

STACK_NAME="metals-pipeline"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Smoke Test"
echo "=========================================="
echo ""

echo "1. Checking services..."
if docker stack services ${STACK_NAME} | grep -q "0/"; then
    echo -e "${RED}✗ Some services have 0 replicas${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Services running${NC}"
echo ""

echo "2. Testing Producer health..."
MAX_RETRIES=30
for i in $(seq 1 $MAX_RETRIES); do
    if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
        RESPONSE=$(curl -s http://localhost:8000/health)
        if echo "$RESPONSE" | grep -q '"kafka_connected":true'; then
            echo -e "${GREEN}✓ Producer healthy${NC}"
            break
        fi
    fi
    if [ $i -eq $MAX_RETRIES ]; then
        echo -e "${RED}✗ Producer not healthy${NC}"
        exit 1
    fi
    echo -e "${YELLOW}⏳ Waiting ($i/$MAX_RETRIES)...${NC}"
    sleep 5
done
echo ""

echo "3. Testing Processor health..."
for i in $(seq 1 $MAX_RETRIES); do
    if curl -sf http://localhost:8001/health > /dev/null 2>&1; then
        RESPONSE=$(curl -s http://localhost:8001/health)
        if echo "$RESPONSE" | grep -q '"kafka_connected":true' && echo "$RESPONSE" | grep -q '"mongodb_status":"connected"'; then
            echo -e "${GREEN}✓ Processor healthy${NC}"
            break
        fi
    fi
    if [ $i -eq $MAX_RETRIES ]; then
        echo -e "${RED}✗ Processor not healthy${NC}"
        exit 1
    fi
    echo -e "${YELLOW}⏳ Waiting ($i/$MAX_RETRIES)...${NC}"
    sleep 5
done
echo ""

echo "4. Sending test message..."
RESPONSE=$(curl -s -X POST http://localhost:8000/produce)
if echo "$RESPONSE" | grep -q '"success":true'; then
    echo -e "${GREEN}✓ Message sent${NC}"
else
    echo -e "${RED}✗ Failed to send${NC}"
    exit 1
fi
echo ""

echo "5. Verifying Kafka..."
KAFKA_CONTAINER=$(docker ps -q -f name=${STACK_NAME}_kafka | head -1)
if [ -n "$KAFKA_CONTAINER" ]; then
    if docker exec $KAFKA_CONTAINER kafka-topics --bootstrap-server localhost:9092 --list | grep -q "metals-prices"; then
        echo -e "${GREEN}✓ Kafka topic exists${NC}"
    fi
fi
echo ""

echo "6. Waiting for processing..."
sleep 30
echo -e "${GREEN}✓ Wait complete${NC}"
echo ""

echo "=========================================="
echo -e "${GREEN}✓ Smoke Test Passed${NC}"
echo "=========================================="
echo ""
echo "Next: Run 'make scaling-test'"
