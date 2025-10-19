# Network Architecture Diagram

## Overview
Three encrypted overlay networks provide isolation between services.

## Network Topology

```
┌─────────────────────────────────────────────────────────────┐
│                    DOCKER SWARM CLUSTER                      │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │         metals-frontend (overlay, encrypted)        │    │
│  │                                                     │    │
│  │    ┌──────────┐              ┌──────────┐         │    │
│  │    │ Producer │─────────────>│  Kafka   │         │    │
│  │    │  :8000   │   Messages   │  :9092   │         │    │
│  │    └──────────┘              └──────────┘         │    │
│  │                                    │               │    │
│  └────────────────────────────────────┼───────────────┘    │
│                                       │                     │
│  ┌────────────────────────────────────┼───────────────┐    │
│  │         metals-backend (overlay, encrypted)    │   │    │
│  │                                    │               │    │
│  │                             ┌──────────┐          │    │
│  │                             │Zookeeper │          │    │
│  │                             │  :2181   │          │    │
│  │                             └──────────┘          │    │
│  │                                    │               │    │
│  │                             ┌──────────┐          │    │
│  │                             │  Kafka   │          │    │
│  │                             │  :9092   │          │    │
│  │                             └──────────┘          │    │
│  │                                    │               │    │
│  │                             ┌──────────┐          │    │
│  │                             │Processor │          │    │
│  │                             │  :8001   │          │    │
│  │                             └──────────┘          │    │
│  │                                    │               │    │
│  │                             ┌──────────┐          │    │
│  │                             │ MongoDB  │          │    │
│  │                             │  :27017  │          │    │
│  │                             └──────────┘          │    │
│  └──────────────────────────────────────────────────────   │
│                                                              │
│  ┌──────────────────────────────────────────────────────   │
│  │         metals-monitoring (overlay)                 │    │
│  │    All services - health endpoints only             │    │
│  └──────────────────────────────────────────────────────   │
│                                                              │
└──────────────────────────────────────────────────────────────┘

External Access:
  • Producer Health: localhost:8000/health
  • Processor Health: localhost:8001/health
```

## Network Details

### metals-frontend
- **Driver**: overlay
- **Encryption**: IPsec enabled
- **Services**: producer, kafka
- **Purpose**: Isolate message ingestion

### metals-backend  
- **Driver**: overlay
- **Encryption**: IPsec enabled
- **Services**: zookeeper, kafka, processor, mongodb
- **Purpose**: Isolate processing and storage

### metals-monitoring
- **Driver**: overlay
- **Encryption**: Not required
- **Services**: All (health endpoints only)
- **Purpose**: Health monitoring

## Security Boundaries

### Access Control
1. **Producer** can only reach:
   - Kafka (via metals-frontend)

2. **Processor** can only reach:
   - Kafka (via metals-backend)
   - MongoDB (via metals-backend)

3. **MongoDB** accessible only by:
   - Processor (via metals-backend)

4. **Kafka** accessible by:
   - Producer (via metals-frontend)
   - Processor (via metals-backend)

### Port Exposure
- **Internal Only**: Kafka (9092), MongoDB (27017), Zookeeper (2181)
- **Published**: Producer (8000), Processor (8001) - health only

## Network Commands

```bash
# List networks
docker network ls | grep metals

# Inspect network
docker network inspect metals-pipeline_metals-frontend

# Test connectivity
docker exec <container> nc -zv kafka 9092
```

## Comparison with CA1

| Aspect | CA1 (AWS) | CA2 (Swarm) |
|--------|-----------|-------------|
| Network | VPC + Subnets | Overlay Networks |
| Isolation | Security Groups | Network Scoping |
| Encryption | TLS | IPsec |
| Discovery | Manual IPs | Automatic DNS |
