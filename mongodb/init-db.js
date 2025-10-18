db = db.getSiblingDB('metals');

db.createCollection('prices');

db.prices.createIndex({ 'event_id': 1 }, { unique: true });
db.prices.createIndex({ 'metal': 1 });
db.prices.createIndex({ 'timestamp': 1 });
db.prices.createIndex({ 'processed_at': 1 });
db.prices.createIndex({ 'metal': 1, 'timestamp': -1 });

db.createView(
  'recent_prices',
  'prices',
  [
    { $sort: { timestamp: -1 } },
    { $limit: 100 }
  ]
);

print('MongoDB initialization complete');
