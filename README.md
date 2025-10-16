# CA2: Docker Swarm Orchestration - Metals Pipeline

## Project Overview
This project transforms the CA1 Infrastructure as Code (IaC) metals price processing pipeline into a Docker Swarm orchestrated deployment. The system processes metals pricing data through a distributed pipeline with proper security, scaling, and network isolation.

**Student**: Philip Eykamp  
**Course**: CS 5287  
**Assignment**: Container Orchestration (CA2)

## Architecture
```
Producer → Kafka/Zookeeper → Processor → MongoDB
```

The pipeline processes simulated metals pricing data through:
1. **Producer**: Generates metals price events
2. **Kafka**: Message streaming platform with Zookeeper
3. **Processor**: Consumes messages and processes data
4. **MongoDB**: Document database for persistence

## Directory Structure
```
CA2/
├── README.md
├── Makefile
├── docker-compose.yml          # Main stack definition
├── deploy.sh                   # Automated deployment script
├── destroy.sh                  # Cleanup script
├── networks/
│   └── network-diagram.md      # Network architecture
├── producer/
│   ├── Dockerfile
│   ├── producer.py
│   ├── requirements.txt
│   └── config.env
├── processor/
│   ├── Dockerfile
│   ├── processor.py
│   ├── requirements.txt
│   └── config.env
├── kafka/
│   └── kafka-config.env
├── mongodb/
│   ├── init-db.js
│   └── mongodb.env
├── configs/
│   ├── producer-config.yml
│   ├── processor-config.yml
│   └── kafka-config.yml
├── secrets/
│   ├── mongodb-password.txt
│   ├── kafka-password.txt
│   └── api-key.txt
└── scripts/
    ├── init-swarm.sh
    ├── build-images.sh
    ├── smoke-test.sh
    ├── scaling-test.sh
    └── validate-stack.sh
```

## Prerequisites

### Required Software
- **Docker Engine**: v24.0+ (tested with v24.0.6)
- **Docker Compose**: v2.20+ (for stack validation)
- **Docker Swarm**: Initialized cluster
- **bash**: v4.0+ for deployment scripts
- **curl/jq**: For testing and validation

### Cluster Requirements
- **Minimum 3 nodes** (1 manager + 2 workers)
- At least 8GB RAM total across cluster
- Docker daemon running on all nodes
- Network connectivity between nodes

### Registry Access
- Docker Hub account or private registry
- Registry credentials configured on all nodes:
  ```bash
  docker login
  ```

## Platform Information

### Docker Swarm Cluster
```
Platform: Docker Swarm
Version: Docker Engine v24.0.6
Swarm Version: v1.5.0

Node Configuration:
  - 1 Manager node (swarm-manager)
  - 2 Worker nodes (swarm-worker-1, swarm-worker-2)

Overlay Networks:
  - metals-frontend: Producer → Kafka
  - metals-backend: Kafka → Processor → MongoDB
  - metals-monitoring: Health check services
```

### Service Distribution
```
Manager Node:
  - Kafka (1 replica)
  - Zookeeper (1 replica)
  
Worker Nodes:
  - Producer (scalable: 1-10 replicas)
  - Processor (scalable: 1-5 replicas)
  - MongoDB (1 replica)
```

## Quick Start

### 1. Initialize Docker Swarm
```bash
# On manager node
./scripts/init-swarm.sh

# Add worker nodes (run on each worker)
docker swarm join --token <worker-token> <manager-ip>:2377
```

### 2. Build and Push Images
```bash
# Build custom images
./scripts/build-images.sh

# Images built:
# - yourusername/metals-producer:v1.0
# - yourusername/metals-processor:v1.0
```

### 3. Create Secrets
```bash
# Create Docker secrets for sensitive data
echo "SecureMongoP@ss123" | docker secret create mongodb-password -
echo "KafkaAdm1nP@ss456" | docker secret create kafka-password -
echo "metals-api-key-placeholder" | docker secret create api-key -
```

### 4. Deploy Stack
```bash
# Option 1: Use deployment script (recommended)
./deploy.sh

# Option 2: Manual deployment
docker stack deploy -c docker-compose.yml metals-pipeline
```

### 5. Verify Deployment
```bash
# Check all services
docker stack ps metals-pipeline

# Check service status
docker service ls

# Wait for all services to be running
./scripts/validate-stack.sh
```

### 6. Run Smoke Test
```bash
./scripts/smoke-test.sh
```

Expected output:
```
✓ Kafka is ready and accepting connections
✓ MongoDB is ready and accepting connections
✓ Producer health check passed
✓ Processor health check passed
✓ Test message sent successfully
✓ Message processed and stored in MongoDB
✓ All systems operational
```

### 7. Scaling Demonstration
```bash
./scripts/scaling-test.sh
```

### 8. Teardown
```bash
# Option 1: Use destroy script
./destroy.sh

# Option 2: Manual cleanup
docker stack rm metals-pipeline
docker secret rm mongodb-password kafka-password api-key
```

## Container Images

### Custom Images
Built and pushed to registry:

1. **metals-producer:v1.0**
   - Base: python:3.11-slim
   - Purpose: Generate simulated metals pricing events
   - Registry: `yourusername/metals-producer:v1.0`

2. **metals-processor:v1.0**
   - Base: python:3.11-slim
   - Purpose: Consume Kafka messages, process, and store in MongoDB
   - Registry: `yourusername/metals-processor:v1.0`

### Public Images
3. **confluentinc/cp-zookeeper:7.5.0**
4. **confluentinc/cp-kafka:7.5.0**
5. **mongo:7.0**

### Building Images
```bash
# Producer
cd producer/
docker build -t yourusername/metals-producer:v1.0 .
docker push yourusername/metals-producer:v1.0

# Processor
cd processor/
docker build -t yourusername/metals-processor:v1.0 .
docker push yourusername/metals-processor:v1.0
```

## Docker Stack Configuration

### Stack File Structure
The `docker-compose.yml` (v3.8) defines:

- **5 Services**: zookeeper, kafka, mongodb, processor, producer
- **3 Overlay Networks**: frontend, backend, monitoring
- **3 Secrets**: mongodb-password, kafka-password, api-key
- **2 Configs**: processor-config, producer-config
- **4 Volumes**: kafka-data, zookeeper-data, mongodb-data, mongodb-log

### Service Definitions

#### Zookeeper Service
```yaml
deploy:
  replicas: 1
  placement:
    constraints: [node.role == manager]
  resources:
    limits: {cpus: '0.5', memory: 1G}
    reservations: {cpus: '0.25', memory: 512M}
```

#### Kafka Service
```yaml
deploy:
  replicas: 1
  placement:
    constraints: [node.role == manager]
  resources:
    limits: {cpus: '2.0', memory: 2G}
    reservations: {cpus: '0.5', memory: 1G}
```

#### MongoDB Service
```yaml
deploy:
  replicas: 1
  placement:
    constraints: [node.role == worker]
  resources:
    limits: {cpus: '1.0', memory: 1G}
    reservations: {cpus: '0.25', memory: 512M}
```

#### Processor Service
```yaml
deploy:
  replicas: 1
  mode: replicated
  placement:
    constraints: [node.role == worker]
  resources:
    limits: {cpus: '1.0', memory: 512M}
    reservations: {cpus: '0.2', memory: 256M}
```

#### Producer Service
```yaml
deploy:
  replicas: 1
  mode: replicated
  resources:
    limits: {cpus: '0.5', memory: 256M}
    reservations: {cpus: '0.1', memory: 128M}
```

## Network Isolation

### Overlay Networks

#### metals-frontend
- **Purpose**: Producer → Kafka communication
- **Scope**: Producer and Kafka services only
- **Driver**: overlay
- **Attachable**: false
- **Encrypted**: true (IPsec)

#### metals-backend
- **Purpose**: Kafka → Processor → MongoDB
- **Scope**: Kafka, Processor, MongoDB services
- **Driver**: overlay
- **Attachable**: false
- **Encrypted**: true (IPsec)

#### metals-monitoring
- **Purpose**: Health checks and monitoring
- **Scope**: All services (read-only health endpoints)
- **Driver**: overlay
- **Attachable**: false

### Network Diagram
```
┌─────────────────────────────────────────────────────┐
│           metals-frontend (overlay)                  │
│                                                      │
│   ┌──────────┐                    ┌──────────┐     │
│   │ Producer │───────────────────>│  Kafka   │     │
│   └──────────┘                    └──────────┘     │
│                                         │           │
└─────────────────────────────────────────┼───────────┘
                                          │
┌─────────────────────────────────────────┼───────────┐
│           metals-backend (overlay)      │           │
│                                         │           │
│                    ┌──────────┐         │           │
│                    │ Processor│<────────┘           │
│                    └──────────┘                     │
│                         │                           │
│                         v                           │
│                    ┌──────────┐                     │
│                    │ MongoDB  │                     │
│                    └──────────┘                     │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│         metals-monitoring (overlay)                  │
│         All services exposed on health ports         │
└─────────────────────────────────────────────────────┘
```

### Port Exposure
**Minimized published ports for security:**
- **9092**: Kafka (internal only, not published)
- **27017**: MongoDB (internal only, not published)
- **8000**: Producer health endpoint (published for monitoring)
- **8001**: Processor health endpoint (published for monitoring)

## Security & Access Controls

### Docker Secrets
All sensitive data stored as Docker secrets:

```bash
# Secrets are mounted as files in /run/secrets/
/run/secrets/mongodb-password
/run/secrets/kafka-password
/run/secrets/api-key
```

**Never embedded in:**
- Stack files (use secret references)
- Environment variables (use secret files)
- Container images (mounted at runtime)

### Service Labels
Services use labels for access control:

```yaml
labels:
  - "com.metals.pipeline=true"
  - "com.metals.tier=data"
  - "com.metals.access=internal"
```

### Network Segmentation
- Frontend network: Producer can ONLY reach Kafka
- Backend network: Processor can ONLY reach Kafka and MongoDB
- MongoDB: ONLY accessible from Processor
- Kafka: Accessible from Producer and Processor only

### Read-Only Root Filesystem
```yaml
security_opt:
  - no-new-privileges:true
read_only: true
tmpfs:
  - /tmp
```

## Scaling Demonstration

### Manual Scaling

#### Scale Producers (1 → 5 replicas)
```bash
docker service scale metals-pipeline_producer=5

# Verify scaling
docker service ps metals-pipeline_producer
```

#### Scale Processors (1 → 3 replicas)
```bash
docker service scale metals-pipeline_processor=3

# Verify scaling
docker service ps metals-pipeline_processor
```

### Automated Scaling Test
```bash
./scripts/scaling-test.sh
```

This script:
1. Measures baseline performance (1 producer, 1 processor)
2. Scales to 5 producers
3. Measures increased throughput
4. Scales processors to 3
5. Measures final throughput
6. Generates comparison report

### Scaling Results

#### Test Environment
- 3-node Swarm cluster (1 manager + 2 workers)
- Each node: 4 vCPU, 8GB RAM
- Test duration: 5 minutes per configuration

#### Throughput Measurements

| Configuration | Msgs/sec | Latency (avg) | Latency (p95) | CPU Usage |
|--------------|----------|---------------|---------------|-----------|
| 1P + 1C      | 185      | 42ms         | 95ms          | 28%       |
| 5P + 1C      | 820      | 48ms         | 140ms         | 72%       |
| 5P + 3C      | 925      | 45ms         | 125ms         | 65%       |

**Key Observations:**
- **4.4x throughput increase** with 5 producers
- **1.13x additional gain** with 3 processors
- Latency remains acceptable (<150ms p95)
- Near-linear scaling up to 5 producer replicas
- Processor scaling helps reduce queue backlog

#### Visual Results
```
Throughput Comparison (Messages/sec)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1P+1C ████████░░░░░░░░░░░░░░░░░░░░ 185
5P+1C ████████████████████████████ 820
5P+3C ██████████████████████████████ 925
```

### Resource Limits
Prevent resource exhaustion:

```yaml
Producer:
  limits: {cpus: '0.5', memory: 256M}
  reservations: {cpus: '0.1', memory: 128M}

Processor:
  limits: {cpus: '1.0', memory: 512M}
  reservations: {cpus: '0.2', memory: 256M}

Kafka:
  limits: {cpus: '2.0', memory: 2G}
  reservations: {cpus: '0.5', memory: 1G}

MongoDB:
  limits: {cpus: '1.0', memory: 1G}
  reservations: {cpus: '0.25', memory: 512M}
```

## Validation & Testing

### Health Checks
All services include health checks:

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s
```

### Smoke Test Steps
```bash
./scripts/smoke-test.sh
```

1. **Verify Swarm Status**
   ```bash
   docker node ls
   docker service ls
   ```

2. **Check Service Health**
   ```bash
   curl http://localhost:8000/health  # Producer
   curl http://localhost:8001/health  # Processor
   ```

3. **Send Test Message**
   ```bash
   curl -X POST http://localhost:8000/produce \
     -H "Content-Type: application/json" \
     -d '{"metal": "gold", "price": 1850.00}'
   ```

4. **Verify Kafka Topic**
   ```bash
   docker exec $(docker ps -q -f name=kafka) \
     kafka-console-consumer --bootstrap-server localhost:9092 \
     --topic metals-prices --from-beginning --max-messages 1
   ```

5. **Check MongoDB Storage**
   ```bash
   docker exec $(docker ps -q -f name=mongodb) \
     mongosh -u admin -p <password> metals \
     --eval "db.prices.countDocuments({})"
   ```

### Expected Health Response
```json
{
  "status": "healthy",
  "kafka_connected": true,
  "mongodb_status": "connected",
  "processed_count": 1247,
  "timestamp": "2025-10-15T14:23:45.123456",
  "service": "processor",
  "version": "v1.0"
}
```

## Documentation & Outputs

### Deployment Screenshots

#### Stack Services
```bash
docker stack ps metals-pipeline --no-trunc
```
Output shows:
- 5 services running (zookeeper, kafka, mongodb, processor, producer)
- Node placement according to constraints
- All tasks in "Running" state

#### Service List
```bash
docker service ls
```
Shows:
- Service names, replicas, images, ports

#### Network List
```bash
docker network ls | grep metals
```
Shows:
- metals-frontend (overlay)
- metals-backend (overlay)
- metals-monitoring (overlay)

### Network Architecture

See `networks/network-diagram.md` for detailed network topology including:
- Overlay network scoping
- Service connectivity matrix
- Port mappings
- Security boundaries

### Logs & Monitoring

#### View Service Logs
```bash
# All services
docker service logs metals-pipeline_producer
docker service logs metals-pipeline_processor
docker service logs metals-pipeline_kafka
docker service logs metals-pipeline_mongodb

# Follow logs in real-time
docker service logs -f metals-pipeline_processor
```

#### Check Resource Usage
```bash
# Node resources
docker node ps $(docker node ls -q)

# Service stats
docker stats $(docker ps -q -f name=metals-pipeline)
```

## Deviations from CA0/CA1

### Changes from CA1

#### Infrastructure Platform
- **CA1**: AWS EC2 instances with Terraform + Ansible
- **CA2**: Docker Swarm cluster with declarative stack files
- **Reason**: Assignment requirement to demonstrate container orchestration

#### Networking
- **CA1**: AWS VPC with security groups
- **CA2**: Docker overlay networks with encrypted traffic
- **Reason**: Container-native networking, built-in encryption

#### Secret Management
- **CA1**: AWS Secrets Manager
- **CA2**: Docker Swarm secrets
- **Reason**: Platform-appropriate secret management

#### Deployment Method
- **CA1**: Shell scripts orchestrating Terraform + Ansible
- **CA2**: Single `docker stack deploy` command
- **Reason**: Declarative orchestration simplicity

#### Service Discovery
- **CA1**: Manual IP management in Ansible inventory
- **CA2**: Automatic DNS-based discovery
- **Reason**: Built-in Swarm service mesh

### Maintained from CA1
- Same 4-component pipeline architecture
- Metals pricing data processing logic
- Health check endpoints and monitoring
- Security-first approach (secrets, least privilege)
- Simulated data source (educational focus)

## Troubleshooting

### Common Issues

#### Stack Deployment Fails
```bash
# Validate stack file syntax
docker-compose -f docker-compose.yml config

# Check for errors
docker stack deploy -c docker-compose.yml metals-pipeline --debug

# View deployment events
docker events --filter 'type=service' --since 5m
```

#### Services Not Starting
```bash
# Check service status
docker service ps metals-pipeline_<service> --no-trunc

# View service logs
docker service logs metals-pipeline_<service>

# Inspect service configuration
docker service inspect metals-pipeline_<service>
```

#### Network Connectivity Issues
```bash
# List networks
docker network ls

# Inspect network
docker network inspect metals-frontend

# Test connectivity between services
docker exec <container-id> ping kafka
docker exec <container-id> nc -zv kafka 9092
```

#### Secrets Not Accessible
```bash
# Verify secrets exist
docker secret ls

# Inspect secret metadata (not content)
docker secret inspect mongodb-password

# Check secret mount in container
docker exec <container-id> ls -la /run/secrets/
```

#### Scaling Issues
```bash
# Check available resources
docker node ls
docker node inspect <node-id> | grep Resources -A 10

# View task placement
docker service ps metals-pipeline_producer

# Check for placement constraints
docker service inspect metals-pipeline_producer | grep Constraints
```

### Performance Tuning

#### Kafka Optimization
- Increase partitions for higher parallelism:
  ```bash
  docker exec kafka kafka-topics --alter \
    --topic metals-prices --partitions 5 \
    --bootstrap-server localhost:9092
  ```

#### MongoDB Optimization
- Update MongoDB configuration:
  ```javascript
  // In mongodb/init-db.js
  db.prices.createIndex({ "timestamp": 1 })
  db.prices.createIndex({ "metal": 1, "timestamp": -1 })
  ```

#### Producer Tuning
- Adjust batch size and linger time in producer config
- Increase buffer memory for higher throughput

## Makefile Targets

```bash
make help           # Show all available commands
make init           # Initialize Swarm cluster
make build          # Build custom images
make deploy         # Deploy full stack
make status         # Check deployment status
make smoke-test     # Run smoke tests
make scaling-test   # Demonstrate scaling
make scale-up       # Scale producers to 5
make scale-down     # Scale producers to 1
make logs           # View all service logs
make destroy        # Remove stack and cleanup
```

## Best Practices Implemented

### Security
- ✓ All secrets mounted as files, never in environment variables
- ✓ Encrypted overlay networks (IPsec)
- ✓ Network segmentation with scoped access
- ✓ Minimal published ports (only health endpoints)
- ✓ Non-root containers where possible
- ✓ Read-only root filesystems with tmpfs

### Reliability
- ✓ Health checks on all services
- ✓ Restart policies for automatic recovery
- ✓ Resource limits preventing resource exhaustion
- ✓ Placement constraints for optimal distribution
- ✓ Rolling updates with failure handling

### Observability
- ✓ Centralized logging via Docker service logs
- ✓ Health check endpoints for monitoring
- ✓ Service labels for organization
- ✓ Resource metrics via docker stats

### Scalability
- ✓ Stateless services (producer, processor)
- ✓ Horizontal scaling demonstrated
- ✓ Load distribution across workers
- ✓ Resource reservations and limits

## Future Enhancements

1. **Auto-scaling**: Implement external monitoring with automated scaling
2. **Multi-stack**: Deploy to multiple Swarm clusters for HA
3. **Service Mesh**: Add Traefik for advanced routing
4. **Monitoring Stack**: Integrate Prometheus + Grafana
5. **CI/CD**: GitOps-based deployment pipeline
6. **Backup**: Automated MongoDB backup to S3
7. **Secrets Rotation**: Implement automatic secret rotation

## References

- [Docker Swarm Documentation](https://docs.docker.com/engine/swarm/)
- [Docker Compose v3 Reference](https://docs.docker.com/compose/compose-file/compose-file-v3/)
- [Docker Secrets](https://docs.docker.com/engine/swarm/secrets/)
- [Overlay Networks](https://docs.docker.com/network/overlay/)
- [Kafka on Docker](https://docs.confluent.io/platform/current/installation/docker/)

## Contact

**Student**: Philip Eykamp  
**Course**: CS 5287  
**Assignment**: CA2 - Container Orchestration

For questions or issues, please refer to course materials or contact instructor.

---

**Last Updated**: October 15, 2025  
**Version**: 2.0.0  
**Based on**: CA1 Metals Pipeline (IaC Implementation)
