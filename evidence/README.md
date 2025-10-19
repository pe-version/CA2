# Visual Evidence - CA2 Docker Swarm

All screenshots captured: October 19, 2025

## Files

1. `01-cluster-status.png` - 3-node Swarm cluster (all Ready/Active)
2. `02-service-list.png` - Service status (Zookeeper 1/1, MongoDB 1/1, Kafka 0/1)
3. `03-kafka-stuck.png` - Kafka task stuck in "New" state
4. `04-working-services.png` - Zookeeper and MongoDB running successfully
5. `05-networks.png` - Overlay networks configured with encryption
6. `06-processor-logs.png` - Processor attempting to connect to Kafka
7. `07-secrets.png` - Docker secrets properly configured
8. `08-infrastructure.png` - Node resources and Docker version
9. `09-aws-instances.png` - AWS EC2 instances (3 t3.small)
10. `10-aws-security-groups.png` - Security group rules

## What This Proves

✅ Infrastructure correctly provisioned  
✅ Swarm cluster operational  
✅ Services that can schedule are working  
✅ Kafka scheduling blocked (documented issue)  
✅ Configuration is correct
