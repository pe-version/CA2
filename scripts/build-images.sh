set -e

echo "=========================================="
echo "Building Container Images"
echo "=========================================="
echo ""

REGISTRY="${REGISTRY:-hiphophippo}"
VERSION="v1.0"

if ! docker info | grep -q "Username"; then
    echo "Warning: Not logged into Docker registry"
    read -p "Login now? (y/N) " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker login
    fi
fi

echo "Building producer..."
cd producer/
docker build -t ${REGISTRY}/metals-producer:${VERSION} .
docker tag ${REGISTRY}/metals-producer:${VERSION} ${REGISTRY}/metals-producer:latest
cd ..

echo "✓ Producer built"
echo ""

echo "Building processor..."
cd processor/
docker build -t ${REGISTRY}/metals-processor:${VERSION} .
docker tag ${REGISTRY}/metals-processor:${VERSION} ${REGISTRY}/metals-processor:latest
cd ..

echo "✓ Processor built"
echo ""

read -p "Push to registry? (y/N) " -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Pushing images..."
    docker push ${REGISTRY}/metals-producer:${VERSION}
    docker push ${REGISTRY}/metals-producer:latest
    docker push ${REGISTRY}/metals-processor:${VERSION}
    docker push ${REGISTRY}/metals-processor:latest
    echo "✓ Images pushed"
fi

echo ""
echo "Build complete:"
echo "  ${REGISTRY}/metals-producer:${VERSION}"
echo "  ${REGISTRY}/metals-processor:${VERSION}"

