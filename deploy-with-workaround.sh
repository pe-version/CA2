#!/bin/bash
set -e

echo "Deploying metals pipeline stack..."
docker stack deploy -c /home/ubuntu/ca2-deployment/docker-compose.aws.yml metals-pipeline

echo "Waiting for base services to start..."
sleep 60

echo "Manually creating Kafka service (workaround for scheduling issue)..."
docker service rm metals-pipeline_kafka 2>/dev/null || true
sleep 5

docker service create \
  --name metals-pipeline_kafka \
  --constraint 'node.role==manager' \
  --network metals-pipeline_metals-backend \
  --network metals-pipeline_metals-frontend \
  --network metals-pipeline_metals-monitoring \
  --env KAFKA_BROKER_ID=1 \
  --env KAFKA_ZOOKEEPER_CONNECT=zookeeper:2181 \
  --env KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://kafka:9092 \
  --env KAFKA_LISTENERS=PLAINTEXT://0.0.0.0:9092 \
  --env KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
  --env KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1 \
  --env KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1 \
  --env KAFKA_AUTO_CREATE_TOPICS_ENABLE=true \
  --env KAFKA_NUM_PARTITIONS=3 \
  --env KAFKA_COMPRESSION_TYPE=snappy \
  --label com.metals.pipeline=true \
  --label com.metals.tier=messaging \
  --label com.metals.service=kafka \
  confluentinc/cp-kafka:7.0.0

echo "Waiting for all services to be ready..."
sleep 90

echo "Deployment complete! Check status with: docker service ls"
