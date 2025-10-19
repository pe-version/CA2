set -e

echo "=========================================="
echo "Initializing Docker Swarm"
echo "=========================================="
echo ""

if docker info | grep -q "Swarm: active"; then
    echo "Docker Swarm already initialized"
    echo ""
    docker node ls
    echo ""
    echo "Worker Join Token:"
    docker swarm join-token worker
    exit 0
fi

# Universal version:
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    IP_ADDR=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1")
else
    # Linux
    IP_ADDR=$(hostname -I | awk '{print $1}')
fi

echo "Detected IP: $IP_ADDR"
echo ""

echo "Initializing swarm..."
docker swarm init --advertise-addr $IP_ADDR

echo ""
echo "✓ Swarm initialized!"
echo ""
docker node ls
echo ""
echo "To add workers, run on each worker:"
docker swarm join-token worker
