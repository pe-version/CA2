"""Metals Price Producer"""

import os
import sys
import json
import time
import random
import logging
from datetime import datetime
from kafka import KafkaProducer
from kafka.errors import KafkaError
from flask import Flask, jsonify
import threading

logging.basicConfig(
    level=os.getenv('LOG_LEVEL', 'INFO'),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

producer = None
kafka_connected = False
messages_sent = 0
error_count = 0        # ADD THIS
last_sent = None       # ADD THIS
last_error = None

KAFKA_BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'kafka:9092')
KAFKA_TOPIC = os.getenv('KAFKA_TOPIC', 'metals-prices')
PRODUCER_INTERVAL = int(os.getenv('PRODUCER_INTERVAL', '5'))

METALS_DATA = {
    'gold': {'base': 1950.0, 'volatility': 50.0, 'unit': 'USD/oz'},
    'silver': {'base': 24.0, 'volatility': 2.0, 'unit': 'USD/oz'},
    'platinum': {'base': 980.0, 'volatility': 40.0, 'unit': 'USD/oz'},
    'palladium': {'base': 1100.0, 'volatility': 80.0, 'unit': 'USD/oz'},
    'copper': {'base': 3.85, 'volatility': 0.15, 'unit': 'USD/lb'},
    'aluminum': {'base': 2.20, 'volatility': 0.10, 'unit': 'USD/lb'},
}

def generate_price(metal):
    data = METALS_DATA[metal]
    base = data['base']
    volatility = data['volatility']
    change_percent = random.gauss(0, volatility / base)
    price = base * (1 + change_percent)
    return round(price, 2)

def generate_event():
    metal = random.choice(list(METALS_DATA.keys()))
    price = generate_price(metal)
    return {
        'event_id': f"{metal}-{int(time.time() * 1000)}-{random.randint(1000, 9999)}",
        'metal': metal,
        'price': price,
        'unit': METALS_DATA[metal]['unit'],
        'timestamp': datetime.utcnow().isoformat(),
        'source': 'metals-producer',
        'market': random.choice(['COMEX', 'LME', 'NYMEX']),
        'volume': random.randint(100, 10000),
    }

def init_kafka_producer():
    global producer, kafka_connected
    max_retries = 10
    for attempt in range(max_retries):
        try:
            logger.info(f"Connecting to Kafka at {KAFKA_BOOTSTRAP_SERVERS} (attempt {attempt + 1})")
            producer = KafkaProducer(
                bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
                value_serializer=lambda v: json.dumps(v).encode('utf-8'),
                key_serializer=lambda k: k.encode('utf-8') if k else None,
                acks='all',
                retries=3,
                compression_type='snappy',
            )
            producer.flush(timeout=10)
            kafka_connected = True
            logger.info("Connected to Kafka")
            return True
        except Exception as e:
            logger.error(f"Kafka connection failed: {e}")
            kafka_connected = False
            if attempt < max_retries - 1:
                time.sleep(5)
    return False

def produce_messages():
    global messages_sent, error_count, last_sent, last_error
    logger.info(f"Starting production. Topic: {KAFKA_TOPIC}, Interval: {PRODUCER_INTERVAL}s")
    while True:
        try:
            if not kafka_connected:
                if not init_kafka_producer():
                    time.sleep(10)
                    continue
            
            event = generate_event()
            future = producer.send(KAFKA_TOPIC, key=event['metal'], value=event)
            record_metadata = future.get(timeout=10)
            messages_sent += 1
            last_sent = datetime.utcnow().isoformat()
            logger.info(f"Sent: {event['metal']} @ ${event['price']} (msg #{messages_sent})")
            last_error = None
            time.sleep(PRODUCER_INTERVAL)
        except Exception as e:
            error_count += 1
            last_error = str(e)
            logger.error(f"Error: {e}")
            kafka_connected = False
            time.sleep(5)

@app.route('/health', methods=['GET'])
def health_check():
    is_healthy = kafka_connected
    
    status = {
        'status': 'healthy' if is_healthy else 'unhealthy',
        'kafka_connected': kafka_connected,
        'messages_sent': messages_sent,
        'last_error': last_error,
        'timestamp': datetime.utcnow().isoformat(),
        'service': 'metals-producer',
        'version': 'v1.0'
    }
    
    return jsonify(status), 200 if is_healthy else 503

@app.route('/produce', methods=['POST'])
def manual_produce():
    try:
        if not kafka_connected:
            return jsonify({'error': 'Kafka not connected'}), 503
        event = generate_event()
        future = producer.send(KAFKA_TOPIC, key=event['metal'], value=event)
        record_metadata = future.get(timeout=10)
        return jsonify({'success': True, 'event': event}), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/stats', methods=['GET'])
def stats():
    return jsonify({
        'messages_sent': messages_sent,
        'kafka_connected': kafka_connected,
        'topic': KAFKA_TOPIC
    }), 200

def start_flask():
    app.run(host='0.0.0.0', port=8000, debug=False, use_reloader=False)

if __name__ == '__main__':
    logger.info("Starting Metals Producer")
    init_kafka_producer()
    flask_thread = threading.Thread(target=start_flask, daemon=True)
    flask_thread.start()
    try:
        produce_messages()
    except KeyboardInterrupt:
        logger.info("Shutting down")
        if producer:
            producer.flush()
            producer.close()
        sys.exit(0)
