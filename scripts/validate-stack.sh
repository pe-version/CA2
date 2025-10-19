set -e

STACK_NAME="metals-pipeline"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Validating Stack"
echo "=========================================="
echo ""

if ! docker stack ls | grep -q ${STACK_NAME}; then
    echo -e "${RED}✗ Stack not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Stack exists${NC}"

echo ""
echo "Services:"
SERVICES=$(docker stack services ${STACK_NAME} --format "{{.Name}}" | wc -l)
if [ "$SERVICES" -ne 5 ]; then
    echo -e "${RED}✗ Expected 5 services, found ${SERVICES}${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All 5 services found${NC}"
docker stack services ${STACK_NAME}

echo ""
echo "Replicas:"
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

echo ""
if [ "$READY" = true ]; then
    echo -e "${GREEN}✓ Validation passed${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠ Some services not ready${NC}"
    exit 1
fi
