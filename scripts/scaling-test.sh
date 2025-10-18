set -e

STACK_NAME="metals-pipeline"
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Scaling Test"
echo "=========================================="
echo ""

get_count() {
    curl -s http://localhost:8001/stats | grep -o '"processed_count":[0-9]*' | cut -d':' -f2
}

measure_throughput() {
    local duration=$1
    local start=$(get_count)
    sleep $duration
    local end=$(get_count)
    echo $((end - start))
}

echo -e "${BLUE}Phase 1: Baseline (1 producer)${NC}"
docker service scale ${STACK_NAME}_producer=1 >/dev/null 2>&1
sleep 30

echo "Measuring (60s)..."
BASELINE=$(measure_throughput 60)
BASELINE_RATE=$(echo "scale=2; $BASELINE / 60" | bc)
echo "Baseline: $BASELINE messages ($BASELINE_RATE msg/s)"
echo ""

echo -e "${BLUE}Phase 2: Scaled (5 producers)${NC}"
docker service scale ${STACK_NAME}_producer=5 >/dev/null 2>&1
sleep 45

echo "Measuring (60s)..."
SCALED=$(measure_throughput 60)
SCALED_RATE=$(echo "scale=2; $SCALED / 60" | bc)
echo "Scaled: $SCALED messages ($SCALED_RATE msg/s)"
echo ""

IMPROVEMENT=$(echo "scale=1; ($SCALED - $BASELINE) * 100 / $BASELINE" | bc)

echo "=========================================="
echo "Results Summary"
echo "=========================================="
echo ""
echo "Configuration    | Messages | Rate      | Improvement"
echo "-----------------|----------|-----------|------------"
echo "1 Producer       | $BASELINE     | ${BASELINE_RATE}/s |     -"
echo "5 Producers      | $SCALED     | ${SCALED_RATE}/s | +${IMPROVEMENT}%"
echo ""
echo "Throughput increased by ${IMPROVEMENT}%"
echo ""
echo "Current services:"
docker service ls --filter name=${STACK_NAME}

