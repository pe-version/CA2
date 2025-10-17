# CA2 - Network Architecture Diagram

## Overview
The Docker Swarm deployment uses three encrypted overlay networks to provide network isolation and security between services.

## Network Topology

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        DOCKER SWARM CLUSTER                              │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │              metals-frontend (overlay, encrypted)               │    │
│  │                                                                 │    │
│  │    ┌─────────────┐                      ┌──────────────┐      │    │
│  │    │  Producer   │─────────────────────>│    Kafka     │      │    │
│  │    │  :8000      │   publish messages   │    :9092     │      │    │
│  │    │  (scalable) │                      │              │      │    │
│  │    └─────────────┘                      └──────────────┘      │    │
│  │         │                                       │              │    │
│  └─────────┼───────────────────────────────────────┼──────────────┘    │
│            │                                       │                    │
│            │                                       │                    │
│  ┌─────────┼───────────────────────────────────────┼──────────────┐    │
│  │         │       metals-backend (overlay, encrypted)     │      │    │
│  │         │                                       │              │    │
│  │         │                    ┌──────────────┐   │              │    │
│  │         │                    │  Zookeeper   │   │              │    │
│  │         │                    │    :2181     │   │              │    │
│  │         │                    └──────────────┘   │              │    │
│  │         │                           │           │              │    │
│  │         │                           v           │              │    │
│  │         │                    ┌──────────────┐   │              │    │
│  │         └───────────────────>│    Kafka     │<──┘              │    │
│  │                              │    :9092     │                  │    │
│  │                              └──────────────┘                  │    │
│  │                                     │                          │    │
│  │                                     v                          │    │
│  │                              ┌──────────────┐                  │    │
│  │                              │  Processor   │                  │    │
│  │                              │    :8001     │                  │    │
│  │                              │  (scalable)  │                  │    │
│  │                              └──────────────┘                  │    │
│  │                                     │                          │    │
│  │                                     v                          │    │
│  │                              ┌──────────────┐                  │    │
│  │                              │   MongoDB    │                  │    │
│  │                              │   :27017     │                  │    │
│  │                              │              │                  │    │
│  │                              └──────────────┘                  │    │
│  └─────────────────────────────────────────────────────────────────    │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────    │
│  │          metals-monitoring (overlay)                            │    │
│  │                                                                 │    │
│  │    All services accessible on health endpoints                 │    │
│  │    Producer:8000/health  |  Processor:8001/health              │    │
│  │                                                                 │    │
│  └─────────────────────────────────────────────────────────────────    │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘

External Access (Published Ports):
  • Producer Health: 8000 (ingress mode)
  • Processor Health: 8001 (ingress mode)
```

## Network Details

### metals-frontend
- **Purpose**: Isolate producer-to-Kafka communication
- **Driver**: overlay
- **Encryption**: IPsec enabled
- **Services**: producer, kafka
- **Traffic Flow**: Producer publishes messages → Kafka receives

### metals-backend
- **Purpose**: Isolate Kafka-Processor-MongoDB communication
- **Driver**: overlay
- **Encryption**: IPsec enabled
- **Services**: zookeeper, kafka, processor, mongodb
- **Traffic Flow**: 
  - Kafka ↔ Zookeeper (coordination)
  - Kafka → Processor (message consumption)
  - Processor → MongoDB (data persistence)

### metals-monitoring
- **Purpose**: Health check and monitoring access
- **Driver**: overlay
- **Encryption**: Not required (read-only health data)
- **Services**: All services
- **Traffic Flow**: External health checks → Service health endpoints

## Service Connectivity Matrix

| From Service | To Service | Network | Port | Protocol | Purpose |
|-------------|------------|---------|------|----------|---------|
| Producer | Kafka | metals-frontend | 9092 | TCP | Publish messages |
| Processor | Kafka | metals-backend | 9092 | TCP | Consume messages |
| Processor | MongoDB | metals-backend | 27017 | TCP | Store data |
| Kafka | Zookeeper | metals-backend | 2181 | TCP | Coordination |
| External | Producer | metals-monitoring | 8000 | HTTP | Health checks |
| External | Processor | metals-monitoring | 8001 | HTTP | Health checks |

## Security Boundaries

### Network Isolation Rules
1. **Producer** can ONLY communicate with:
   - Kafka (via metals-frontend)
   - External (health endpoint via metals-monitoring)

2. **Processor** can ONLY communicate with:
   - Kafka (via metals-backend)
   - MongoDB (via metals-backend)
   - External (health endpoint via metals-monitoring)

3. **MongoDB** can ONLY be accessed by:
   - Processor (via metals-backend)

4. **Kafka** is accessible by:
   - Producer (via metals-frontend)
   - Processor (via metals-backend)
   - Zookeeper (via metals-backend)

### Port Exposure Strategy
- **Internal Only** (not published):
  - Kafka: 9092
  - MongoDB: 27017
  - Zookeeper: 2181

- **Published** (ingress mode for load balancing):
  - Producer health: 8000
  - Processor health: 8001

## Overlay Network Features

### Encryption
All overlay networks use IPsec encryption for:
- Data confidentiality
- Data integrity
- Protection against eavesdropping

### Service Discovery
- Automatic DNS-based service discovery
- Services accessible by name (e.g., `kafka`, `mongodb`)
- VIP (Virtual IP) load balancing for scaled services

### Load Balancing
- Ingress mode: External load balancing across all nodes
- VIP mode: Internal round-robin to service replicas
- Connection-based load distribution

## Network Commands

### Inspect Networks
```bash
# List all networks
docker network ls | grep metals

# Inspect specific network
docker network inspect metals-frontend
docker network inspect metals-backend
docker network inspect metals-monitoring
```

### Verify Service Connectivity
```bash
# Test producer to kafka
docker exec $(docker ps -q -f name=producer) nc -zv kafka 9092

# Test processor to kafka
docker exec $(docker ps -q -f name=processor) nc -zv kafka 9092

# Test processor to mongodb
docker exec $(docker ps -q -f name=processor) nc -zv mongodb 27017
```

### Network Traffic
```bash
# View network-related logs
docker service logs metals-pipeline_producer | grep -i network
docker service logs metals-pipeline_processor | grep -i connection
```

## Network Performance

### Latency Characteristics
- **Overlay network overhead**: ~1-2ms
- **Encryption overhead**: ~0.5-1ms
- **Total network latency**: 2-3ms (within same datacenter)

### Throughput
- **Overlay network bandwidth**: Limited by physical network
- **Typical throughput**: 5-10 Gbps per connection
- **No significant bottleneck for message streaming**

## Comparison with CA1

| Aspect | CA1 (AWS EC2) | CA2 (Docker Swarm) |
|--------|---------------|-------------------|
| Network Type | VPC with Subnets | Overlay Networks |
| Isolation | Security Groups | Network Scoping |
| Encryption | TLS (application) | IPsec (network) |
| Service Discovery | Manual IPs | Automatic DNS |
| Load Balancing | Not implemented | Built-in VIP |
| Complexity | High | Low |
| Management | Terraform + Ansible | Docker Stack |

## Troubleshooting

### Network Connectivity Issues

1. **Producer cannot reach Kafka**
   ```bash
   # Check if producer is on correct network
   docker service inspect metals-pipeline_producer | grep Networks
   
   # Verify network exists
   docker network inspect metals-frontend
   ```

2. **Processor cannot reach MongoDB**
   ```bash
   # Check processor networks
   docker service inspect metals-pipeline_processor | grep Networks
   
   # Test connectivity
   docker exec $(docker ps -q -f name=processor) nc -zv mongodb 27017
   ```

3. **Services cannot resolve DNS**
   ```bash
   # Check DNS resolution
   docker exec $(docker ps -q -f name=processor) nslookup kafka
   docker exec $(docker ps -q -f name=processor) nslookup mongodb
   ```

### Network Cleanup
```bash
# Remove all stack networks (after stack removal)
docker network rm metals-pipeline_metals-frontend
docker network rm metals-pipeline_metals-backend
docker network rm metals-pipeline_metals-monitoring
```

## Security Considerations

### Encrypted Networks
- All overlay networks use encrypted data plane
- IPsec encryption protects data in transit
- Control plane uses mutual TLS

### No Direct External Access
- Kafka and MongoDB are NOT exposed externally
- Only health endpoints are published
- All data traffic is internal

### Network Segmentation
- Frontend network isolates ingestion
- Backend network isolates processing and storage
- Monitoring network provides observability without data access

## Future Enhancements

1. **Service Mesh Integration**: Add Istio/Linkerd for advanced traffic management
2. **Multi-datacenter**: Extend overlay networks across regions
3. **Network Policies**: Add more granular traffic rules
4. **Monitoring**: Integrate with Prometheus for network metrics
5. **Rate Limiting**: Implement per-service bandwidth limits

---

**Note**: This network architecture follows security best practices:
- Principle of least privilege (minimal network access)
- Defense in depth (multiple network layers)
- Encrypted communication
- No unnecessary port exposure