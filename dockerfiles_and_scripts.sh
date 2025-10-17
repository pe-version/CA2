# producer/Dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY producer.py .

# Create non-root user
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=45s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

CMD ["python", "producer.py"]

# ===================================================
# producer/requirements.txt
# ===================================================
kafka-python==2.0.2
flask==3.0.0
werkzeug==3.0.1

# ===================================================
# processor/Dockerfile
# ===================================================
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY processor.py .

# Create non-root user
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app

USER appuser

EXPOSE 8001

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8001/health || exit 1

CMD ["python", "processor.py"]

# ===================================================
# processor/requirements.txt
# ===================================================
kafka-python==2.0.2
pymongo==4.6.0
flask==3.0.0
werkzeug==3.0.1

# ===================================================
# mongodb/init-db.js
# ===================================================
// Initialize MongoDB database and collections
db = db.getSiblingDB('metals');

// Create collections
db.createCollection('prices');

// Create indexes
db.prices.createIndex({ 'event_id': 1 }, { unique: true });
db.prices.createIndex({ 'metal': 1 });
db.prices.createIndex({ 'timestamp': 1 });
db.prices.createIndex({ 'processed_at': 1 });
db.prices.createIndex({ 'metal': 1, 'timestamp': -1 });

// Create view for recent prices
db.createView(
  'recent_prices',
  'prices',
  [
    { $sort: { timestamp: -1 } },
    { $limit: 100 }
  ]
);

print('MongoDB initialization complete');

# ===================================================
# configs/processor-config.yml
# ===================================================
processor:
  name: metals-processor
  version: v1.0
  batch_size: 50
  commit_interval: 5
  
kafka:
  topic: metals-prices
  group_id: metals-processor-group
  
mongodb:
  database: metals
  collection: prices
  
logging:
  level: INFO
  format: json

# ===================================================
# configs/producer-config.yml
# ===================================================
producer:
  name: metals-producer
  version: v1.0
  interval: 5
  
kafka:
  topic: metals-prices
  compression: snappy
  batch_size: 16384
  
metals:
  - gold
  - silver
  - platinum
  - palladium
  - copper
  - aluminum