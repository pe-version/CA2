#!/usr/bin/env python3
"""
Metals Price Processor - Docker Swarm Version
Consumes messages from Kafka and stores in MongoDB
"""

import os
import sys
import json
import time
import logging
from datetime import datetime
from typing import Dict, List
from kafka import KafkaConsumer
from kafka.errors import KafkaError
from pymongo import MongoClient
from pymongo.errors import PyMongoError
from flask import Flask, jsonify

# Configure logging
logging.basicConfig(
    level=os.getenv('LOG_LEVEL', 'INFO'),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Flask app for health checks
app = Flask(__name__)

# Global state
consumer = None
mongo_client = None
db = None
collection = None
kafka_connected = False
mongodb_connected = False
processed_count = 0
error_count = 0
last_processed = None
last_error = None

# Configuration from environment
KAFKA_BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'kafka:9092')
KAFKA_TOPIC = os.getenv('KAFKA_TOPIC', 'metals-prices')
KAFKA_GROUP_ID = os.getenv('KAFKA_GROUP_ID', 'metals-processor-group')
MONGODB_HOST = os.getenv('MONGODB_HOST', 'mongodb')
MONGODB_PORT = int(os.getenv('MONGODB_PORT', '27017'))
MONGODB_DATABASE = os.getenv('MONGODB_DATABASE', 'metals')
MONGODB_USERNAME = os.getenv('MONGODB_USERNAME', 'admin')
PROCESSOR_BATCH_SIZE = int(os.getenv('PROCESSOR_BATCH_SIZE', '50'))
PROCESSOR_COMMIT_INTERVAL = int(os.getenv('PROCESSOR_COMMIT_INTERVAL', '5'))

# Read MongoDB password from secret
MONGODB_PASSWORD = None
try:
    with open('/run/secrets/mongodb-password', 'r') as f:
        MONGODB_PASSWORD = f.read().strip()
except Exception as e:
    logger.error(f"Failed to read MongoDB password: {e}")
    MONGODB_PASSWORD = os.getenv('MONGODB_PASSWORD', 'password')


def init_mongodb():
    """Initialize MongoDB connection"""
    global mongo_client, db, collection, mongodb_connected
    
    max_retries = 10
    retry_delay = 5
    
    for attempt in range(max_retries):
        try:
            logger.info(f"Connecting to MongoDB at {MONGODB_HOST}:{MONGODB_PORT} (attempt {attempt + 1}/{max_retries})")
            
            mongo_client = MongoClient(
                host=MONGODB_HOST,
                port=MONGODB_PORT,
                username=MONGODB_USERNAME,
                password=MONGODB_PASSWORD,
                authSource='admin',
                serverSelectionTimeoutMS=5000,
                connectTimeoutMS=5000
            )
            
            # Test connection
            mongo_client.admin.command('ping')
            
            db = mongo_client[MONGODB_DATABASE]
            collection = db['prices']
            
            # Create indexes
            collection.create_index('event_id', unique=True)
            collection.create_index('metal')
            collection.create_index('timestamp')
            collection.create_index('processed_at')
            
            mongodb_connected = True
            logger.info("Successfully connected to MongoDB")
            return True
            
        except PyMongoError as e:
            logger.error(f"MongoDB connection failed: {e}")
            mongodb_connected = False
            
            if attempt < max_retries - 1:
                logger.info(f"Retrying in {retry_delay} seconds...")
                time.sleep(retry_delay)
            else:
                logger.error("Max retries reached. MongoDB connection failed.")
                return False
    
    return False


def init_kafka_consumer():
    """Initialize Kafka consumer"""
    global consumer, kafka_connected
    
    max_retries = 10
    retry_delay = 5
    
    for attempt in range(max_retries):
        try:
            logger.info(f"Connecting to Kafka at {KAFKA_BOOTSTRAP_SERVERS} (attempt {attempt + 1}/{max_retries})")
            
            consumer = KafkaConsumer(
                KAFKA_TOPIC,
                bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
                group_id=KAFKA_GROUP_ID,
                value_deserializer=lambda m: json.loads(m.decode('utf-8')),
                key_deserializer=lambda k: k.decode('utf-8') if k else None,
                auto_offset_reset='earliest',
                enable_auto_commit=False,
                max_poll_records=PROCESSOR_BATCH_SIZE,
                max_poll_interval_ms=300000,
                session_timeout_ms=30000,
                heartbeat_interval_ms=10000,
                api_version=(2, 8, 0)
            )
            
            # Test connection by getting partitions
            partitions = consumer.partitions_for_topic(KAFKA_TOPIC)
            
            kafka_connected = True
            logger.info(f"Successfully connected to Kafka. Topic '{KAFKA_TOPIC}' has {len(partitions)} partitions")
            return True
            
        except KafkaError as e:
            logger.error(f"Kafka connection failed: {e}")
            kafka_connected = False
            
            if attempt < max_retries - 1:
                logger.info(f"Retrying in {retry_delay} seconds...")
                time.sleep(retry_delay)
            else:
                logger.error("Max retries reached. Kafka connection failed.")
                return False
    
    return False


def process_message(message: Dict) -> bool:
    """Process a single message and store in MongoDB"""
    global processed_count, error_count, last_processed, last_error
    
    try:
        # Add processing metadata
        document = {
            **message,
            'processed_at': datetime.utcnow(),
            'processor_id': os.getenv('HOSTNAME', 'unknown'),
            'processor_version': 'v1.0'
        }
        
        # Insert into MongoDB (upsert to handle duplicates)
        result = collection.update_one(
            {'event_id': message['event_id']},
            {'$set': document},
            upsert=True
        )
        
        processed_count += 1
        last_processed = message['event_id']
        
        if result.upserted_id:
            logger.info(f"Processed new event: {message['metal']} @ ${message['price']} (ID: {message['event_id']})")
        else:
            logger.debug(f"Updated existing event: {message['event_id']}")
        
        return True
        
    except PyMongoError as e:
        error_count += 1
        last_error = str(e)
        logger.error(f"Failed to store message in MongoDB: {e}")
        return False
    except Exception as e:
        error_count += 1
        last_error = str(e)
        logger.error(f"Unexpected error processing message: {e}")
        return False


def consume_messages():
    """Main consumer loop"""
    logger.info(f"Starting message consumption. Topic: {KAFKA_TOPIC}, Group: {KAFKA_GROUP_ID}")
    
    batch = []
    last_commit_time = time.time()
    
    while True:
        try:
            # Check connections
            if not kafka_connected:
                logger.warning("Kafka not connected. Attempting to reconnect...")
                if not init_kafka_consumer():
                    time.sleep(10)
                    continue
            
            if not mongodb_connected:
                logger.warning("MongoDB not connected. Attempting to reconnect...")
                if not init_mongodb():
                    time.sleep(10)
                    continue
            
            # Poll for messages
            messages = consumer.poll(timeout_ms=1000, max_records=PROCESSOR_BATCH_SIZE)
            
            if not messages:
                # Periodic commit even without new messages
                if time.time() - last_commit_time > PROCESSOR_COMMIT_INTERVAL:
                    if batch:
                        consumer.commit()
                        logger.debug(f"Committed offsets (periodic)")
                        batch.clear()
                        last_commit_time = time.time()
                continue
            
            # Process messages
            for topic_partition, records in messages.items():
                for record in records:
                    if process_message(record.value):
                        batch.append(record)
                    
                    # Commit batch
                    if len(batch) >= PROCESSOR_BATCH_SIZE:
                        consumer.commit()
                        logger.info(f"Processed and committed batch of {len(batch)} messages")
                        batch.clear()
                        last_commit_time = time.time()
            
            # Time-based commit
            if time.time() - last_commit_time > PROCESSOR_COMMIT_INTERVAL:
                if batch:
                    consumer.commit()
                    logger.info(f"Committed batch of {len(batch)} messages (time-based)")
                    batch.clear()
                    last_commit_time = time.time()
            
        except KafkaError as e:
            logger.error(f"Kafka error: {e}")
            kafka_connected = False
            time.sleep(5)
            
        except PyMongoError as e:
            logger.error(f"MongoDB error: {e}")
            mongodb_connected = False
            time.sleep(5)
            
        except Exception as e:
            logger.error(f"Unexpected error: {e}")
            time.sleep(5)


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    status = {
        'status': 'healthy' if (kafka_connected and mongodb_connected) else 'unhealthy',
        'kafka_connected': kafka_connected,
        'mongodb_status': 'connected' if mongodb_connected else 'disconnected',
        'processed_count': processed_count,
        'error_count': error_count,
        'last_processed': last_processed,
        'last_error': last_error,
        'timestamp': datetime.utcnow().isoformat(),
        'service': 'metals-processor',
        'version': 'v1.0',
        'kafka_bootstrap': KAFKA_BOOTSTRAP_SERVERS,
        'mongodb_host': f"{MONGODB_HOST}:{MONGODB_PORT}",
        'topic': KAFKA_TOPIC,
        'group_id': KAFKA_GROUP_ID
    }
    
    status_code = 200 if (kafka_connected and mongodb_connected) else 503
    return jsonify(status), status_code


@app.route('/stats', methods=['GET'])
def stats():
    """Statistics endpoint"""
    try:
        # Get MongoDB stats
        total_documents = collection.count_documents({}) if mongodb_connected else 0
        
        # Get latest processed document
        latest = None
        if mongodb_connected:
            latest_doc = collection.find_one(sort=[('processed_at', -1)])
            if latest_doc:
                latest = {
                    'event_id': latest_doc.get('event_id'),
                    'metal': latest_doc.get('metal'),
                    'price': latest_doc.get('price'),
                    'processed_at': latest_doc.get('processed_at').isoformat() if latest_doc.get('processed_at') else None
                }
        
        return jsonify({
            'processed_count': processed_count,
            'error_count': error_count,
            'total_documents': total_documents,
            'latest_document': latest,
            'kafka_connected': kafka_connected,
            'mongodb_connected': mongodb_connected,
            'uptime': time.time()
        }), 200
        
    except Exception as e:
        logger.error(f"Stats endpoint error: {e}")
        return jsonify({'error': str(e)}), 500


def start_flask():
    """Start Flask health check server"""
    app.run(host='0.0.0.0', port=8001, debug=False, use_reloader=False)


if __name__ == '__main__':
    import threading
    
    logger.info("Starting Metals Price Processor...")
    logger.info(f"Kafka Bootstrap Servers: {KAFKA_BOOTSTRAP_SERVERS}")
    logger.info(f"Topic: {KAFKA_TOPIC}")
    logger.info(f"Group ID: {KAFKA_GROUP_ID}")
    logger.info(f"MongoDB: {MONGODB_HOST}:{MONGODB_PORT}")
    logger.info(f"Database: {MONGODB_DATABASE}")
    
    # Initialize connections
    mongodb_success = init_mongodb()
    kafka_success = init_kafka_consumer()
    
    if not mongodb_success or not kafka_success:
        logger.error("Initial connections failed. Will retry in background.")
    
    # Start Flask in a separate thread
    flask_thread = threading.Thread(target=start_flask, daemon=True)
    flask_thread.start()
    
    # Start consuming messages
    try:
        consume_messages()
    except KeyboardInterrupt:
        logger.info("Shutting down gracefully...")
        if consumer:
            consumer.close()
        if mongo_client:
            mongo_client.close()
        sys.exit(0)