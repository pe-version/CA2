#!/usr/bin/env python3
"""
Metals Price Producer - Docker Swarm Version
Generates simulated metals pricing data and publishes to Kafka
"""

import os
import sys
import json
import time
import random
import logging
from datetime import datetime
from typing import Dict, List
from kafka import KafkaProducer
from kafka.errors import KafkaError
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
producer = None
kafka_connected = False
messages_sent = 0
last_error = None

# Configuration from environment
KAFKA_BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'kafka:9092')
KAFKA_TOPIC = os.getenv('KAFKA_TOPIC', 'metals-prices')
PRODUCER_INTERVAL = int(os.getenv('PRODUCER_INTERVAL', '5'))

# Metals data with realistic price ranges
METALS_DATA = {
    'gold': {'base': 1950.0, 'volatility': 50.0, 'unit': 'USD/oz'},
    'silver': {'base': 24.0, 'volatility': 2.0, 'unit': 'USD/oz'},
    'platinum': {'base': 980.0, 'volatility': 40.0, 'unit': 'USD/oz'},
    'palladium': {'base': 1100.0, 'volatility': 80.0, 'unit': 'USD/oz'},
    'copper': {'base': 3.85, 'volatility': 0.15, 'unit': 'USD/lb'},
    'aluminum': {'base': 2.20, 'volatility': 0.10, 'unit': 'USD/lb'},
    'zinc': {'base': 1.15, 'volatility': 0.08, 'unit': 'USD/lb'},
    'nickel': {'base': 7.50, 'volatility': 0.40, 'unit': 'USD/lb'}
}


def generate_price(metal: str) -> float:
    """Generate a realistic price for a metal with some volatility"""
    data = METALS_DATA[metal]
    base = data['base']
    volatility = data['volatility']
    
    # Random walk with mean reversion
    change_percent = random.gauss(0, volatility / base)
    price = base * (1 + change_percent)
    
    return round(price, 2)


def generate_metals_event() -> Dict:
    """Generate a metals pricing event"""
    metal = random.choice(list(METALS_DATA.keys()))
    price = generate_price(metal)
    
    event = {
        'event_id': f"{metal}-{int(time.time() * 1000)}-{random.randint(1000, 9999)}",
        'metal': metal,
        'price': price,
        'unit': METALS_DATA[metal]['unit'],
        'timestamp': datetime.utcnow().isoformat(),
        'source': 'metals-producer',
        'market': random.choice(['COMEX', 'LME', 'NYMEX', 'MCX']),
        'volume': random.randint(100, 10000),
        'bid': round(price * 0.998, 2),
        'ask': round(price * 1.002, 2)
    }
    
    return event


def init_kafka_producer():
    """Initialize Kafka producer with retry logic"""
    global producer, kafka_connected
    
    max_retries = 10
    retry_delay = 5
    
    for attempt in range(max_retries):
        try:
            logger.info(f"Connecting to Kafka at {KAFKA_BOOTSTRAP_SERVERS} (attempt {attempt + 1}/{max_retries})")
            
            producer = KafkaProducer(
                bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
                value_serializer=lambda v: json.dumps(v).encode('utf-8'),
                key_serializer=lambda k: k.encode('utf-8') if k else None,
                acks='all',
                retries=3,
                max_in_flight_requests_per_connection=5,
                compression_type='snappy',
                batch_size=16384,
                linger_ms=10,
                buffer_memory=33554432,
                request_timeout_ms=30000,
                api_version=(2, 8, 0)
            )
            
            # Test connection
            producer.flush(timeout=10)
            
            kafka_connected = True
            logger.info("Successfully connected to Kafka")
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


def produce_messages():
    """Main producer loop"""
    global messages_sent, last_error
    
    logger.info(f"Starting message production. Topic: {KAFKA_TOPIC}, Interval: {PRODUCER_INTERVAL}s")
    
    while True:
        try:
            if not kafka_connected:
                logger.warning("Kafka not connected. Attempting to reconnect...")
                if not init_kafka_producer():
                    time.sleep(10)
                    continue
            
            # Generate and send event
            event = generate_metals_event()
            
            # Use metal name as partition key for consistent routing
            future = producer.send(
                KAFKA_TOPIC,
                key=event['metal'],
                value=event
            )
            
            # Wait for send to complete
            record_metadata = future.get(timeout=10)
            
            messages_sent += 1
            
            logger.info(
                f"Sent message {messages_sent}: {event['metal']} @ ${event['price']} "
                f"(partition: {record_metadata.partition}, offset: {record_metadata.offset})"
            )
            
            last_error = None
            time.sleep(PRODUCER_INTERVAL)
            
        except KafkaError as e:
            last_error = str(e)
            logger.error(f"Failed to send message: {e}")
            kafka_connected = False
            time.sleep(5)
            
        except Exception as e:
            last_error = str(e)
            logger.error(f"Unexpected error: {e}")
            time.sleep(5)


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    status = {
        'status': 'healthy' if kafka_connected else 'unhealthy',
        'kafka_connected': kafka_connected,
        'messages_sent': messages_sent,
        'last_error': last_error,
        'timestamp': datetime.utcnow().isoformat(),
        'service': 'metals-producer',
        'version': 'v1.0',
        'kafka_bootstrap': KAFKA_BOOTSTRAP_SERVERS,
        'topic': KAFKA_TOPIC
    }
    
    status_code = 200 if kafka_connected else 503
    return jsonify(status), status_code


@app.route('/produce', methods=['POST'])
def manual_produce():
    """Manual message production endpoint for testing"""
    try:
        if not kafka_connected:
            return jsonify({'error': 'Kafka not connected'}), 503
        
        event = generate_metals_event()
        
        future = producer.send(
            KAFKA_TOPIC,
            key=event['metal'],
            value=event
        )
        
        record_metadata = future.get(timeout=10)
        
        return jsonify({
            'success': True,
            'event': event,
            'partition': record_metadata.partition,
            'offset': record_metadata.offset
        }), 200
        
    except Exception as e:
        logger.error(f"Manual produce failed: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/stats', methods=['GET'])
def stats():
    """Statistics endpoint"""
    return jsonify({
        'messages_sent': messages_sent,
        'kafka_connected': kafka_connected,
        'uptime': time.time(),
        'metals_tracked': list(METALS_DATA.keys()),
        'topic': KAFKA_TOPIC
    }), 200


def start_flask():
    """Start Flask health check server"""
    app.run(host='0.0.0.0', port=8000, debug=False, use_reloader=False)


if __name__ == '__main__':
    import threading
    
    logger.info("Starting Metals Price Producer...")
    logger.info(f"Kafka Bootstrap Servers: {KAFKA_BOOTSTRAP_SERVERS}")
    logger.info(f"Topic: {KAFKA_TOPIC}")
    logger.info(f"Production Interval: {PRODUCER_INTERVAL}s")
    
    # Initialize Kafka connection
    if not init_kafka_producer():
        logger.error("Initial Kafka connection failed. Will retry in background.")
    
    # Start Flask in a separate thread
    flask_thread = threading.Thread(target=start_flask, daemon=True)
    flask_thread.start()
    
    # Start producing messages
    try:
        produce_messages()
    except KeyboardInterrupt:
        logger.info("Shutting down gracefully...")
        if producer:
            producer.flush()
            producer.close()
        sys.exit(0)