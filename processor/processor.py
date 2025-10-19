"""Metals Price Processor"""

import os
import sys
import json
import time
import logging
from datetime import datetime
from kafka import KafkaConsumer
from kafka.errors import KafkaError
from pymongo import MongoClient
from pymongo.errors import PyMongoError
from flask import Flask, jsonify
import threading

logging.basicConfig(
    level=os.getenv('LOG_LEVEL', 'INFO'),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

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

KAFKA_BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'kafka:9092')
KAFKA_TOPIC = os.getenv('KAFKA_TOPIC', 'metals-prices')
KAFKA_GROUP_ID = os.getenv('KAFKA_GROUP_ID', 'metals-processor-group')
MONGODB_HOST = os.getenv('MONGODB_HOST', 'mongodb')
MONGODB_PORT = int(os.getenv('MONGODB_PORT', '27017'))
MONGODB_DATABASE = os.getenv('MONGODB_DATABASE', 'metals')
MONGODB_USERNAME = os.getenv('MONGODB_USERNAME', 'admin')
PROCESSOR_BATCH_SIZE = int(os.getenv('PROCESSOR_BATCH_SIZE', '50'))

MONGODB_PASSWORD = None
try:
    with open('/run/secrets/mongodb-password', 'r') as f:
        MONGODB_PASSWORD = f.read().strip()
except Exception as e:
    logger.error(f"Failed to read MongoDB password: {e}")
    MONGODB_PASSWORD = os.getenv('MONGODB_PASSWORD', 'password')

def init_mongodb():
    global mongo_client, db, collection, mongodb_connected
    max_retries = 10
    for attempt in range(max_retries):
        try:
            logger.info(f"Connecting to MongoDB at {MONGODB_HOST}:{MONGODB_PORT} (attempt {attempt + 1})")
            mongo_client = MongoClient(
                host=MONGODB_HOST,
                port=MONGODB_PORT,
                username=MONGODB_USERNAME,
                password=MONGODB_PASSWORD,
                authSource='admin',
                serverSelectionTimeoutMS=5000,
            )
            mongo_client.admin.command('ping')
            db = mongo_client[MONGODB_DATABASE]
            collection = db['prices']
            collection.create_index('event_id', unique=True)
            collection.create_index('metal')
            collection.create_index('timestamp')
            mongodb_connected = True
            logger.info("Connected to MongoDB")
            return True
        except Exception as e:
            logger.error(f"MongoDB connection failed: {e}")
            mongodb_connected = False
            if attempt < max_retries - 1:
                time.sleep(5)
    return False

def init_kafka_consumer():
    global consumer, kafka_connected
    max_retries = 10
    for attempt in range(max_retries):
        try:
            logger.info(f"Connecting to Kafka at {KAFKA_BOOTSTRAP_SERVERS} (attempt {attempt + 1})")
            consumer = KafkaConsumer(
                KAFKA_TOPIC,
                bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
                group_id=KAFKA_GROUP_ID,
                value_deserializer=lambda m: json.loads(m.decode('utf-8')),
                auto_offset_reset='earliest',
                enable_auto_commit=False,
                max_poll_records=PROCESSOR_BATCH_SIZE,
            )
            # Fixed issue of topic not being created early enough
            partitions = consumer.partitions_for_topic(KAFKA_TOPIC)
            if partitions is None:
                logger.warning(f"Topic '{KAFKA_TOPIC}' doesn't exist yet, will be created automatically")
                partitions = set()
            kafka_connected = True
            logger.info(f"Connected to Kafka. Topic has {len(partitions) if partitions else 0} partitions")
            return True
        except Exception as e:
            logger.error(f"Kafka connection failed: {e}")
            kafka_connected = False
            if attempt < max_retries - 1:
                time.sleep(5)
    return False

def process_message(message):
    global processed_count, error_count, last_processed, last_error
    try:
        document = {
            **message,
            'processed_at': datetime.utcnow(),
            'processor_id': os.getenv('HOSTNAME', 'unknown'),
        }
        result = collection.update_one(
            {'event_id': message['event_id']},
            {'$set': document},
            upsert=True
        )
        processed_count += 1
        last_processed = message['event_id']
        if result.upserted_id:
            logger.info(f"Processed: {message['metal']} @ ${message['price']}")
        return True
    except Exception as e:
        error_count += 1
        last_error = str(e)
        logger.error(f"Processing error: {e}")
        return False

def consume_messages():
    logger.info(f"Starting consumption. Topic: {KAFKA_TOPIC}, Group: {KAFKA_GROUP_ID}")
    batch = []
    last_commit_time = time.time()
    
    while True:
        try:
            if not kafka_connected:
                if not init_kafka_consumer():
                    time.sleep(10)
                    continue
            
            if not mongodb_connected:
                if not init_mongodb():
                    time.sleep(10)
                    continue
            
            messages = consumer.poll(timeout_ms=1000, max_records=PROCESSOR_BATCH_SIZE)
            
            if not messages:
                if time.time() - last_commit_time > 5:
                    if batch:
                        consumer.commit()
                        batch.clear()
                        last_commit_time = time.time()
                continue
            
            for topic_partition, records in messages.items():
                for record in records:
                    if process_message(record.value):
                        batch.append(record)
                    
                    if len(batch) >= PROCESSOR_BATCH_SIZE:
                        consumer.commit()
                        logger.info(f"Committed batch of {len(batch)}")
                        batch.clear()
                        last_commit_time = time.time()
            
            if time.time() - last_commit_time > 5 and batch:
                consumer.commit()
                batch.clear()
                last_commit_time = time.time()
                
        except Exception as e:
            logger.error(f"Error: {e}")
            kafka_connected = False
            mongodb_connected = False
            time.sleep(5)

@app.route('/health', methods=['GET'])
def health_check():
    is_healthy = kafka_connected and mongodb_connected
    
    status = {
        'status': 'healthy' if is_healthy else 'unhealthy',
        'kafka_connected': kafka_connected,
        'mongodb_status': 'connected' if mongodb_connected else 'disconnected',
        'processed_count': processed_count,
        'error_count': error_count,
        'last_processed': last_processed,
        'last_error': last_error,
        'timestamp': datetime.utcnow().isoformat(),
        'service': 'metals-processor',
        'version': 'v1.0'
    }
    
    # Return 503 (Service Unavailable) if not healthy
    return jsonify(status), 200 if is_healthy else 503

@app.route('/stats', methods=['GET'])
def stats():
    try:
        total_docs = collection.count_documents({}) if mongodb_connected else 0
        return jsonify({
            'processed_count': processed_count,
            'error_count': error_count,
            'total_documents': total_docs,
            'kafka_connected': kafka_connected,
            'mongodb_connected': mongodb_connected,
        }), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

def start_flask():
    app.run(host='0.0.0.0', port=8001, debug=False, use_reloader=False)

if __name__ == '__main__':
    logger.info("Starting Metals Processor")
    init_mongodb()
    init_kafka_consumer()
    flask_thread = threading.Thread(target=start_flask, daemon=True)
    flask_thread.start()
    try:
        consume_messages()
    except KeyboardInterrupt:
        logger.info("Shutting down")
        if consumer:
            consumer.close()
        if mongo_client:
            mongo_client.close()
        sys.exit(0)
