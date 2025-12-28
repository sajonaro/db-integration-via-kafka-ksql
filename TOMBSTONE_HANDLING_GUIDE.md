# DELETE Tombstone Handling Guide

## 🎯 Overview

This guide documents the solution for proper DELETE tombstone handling in the Kafka-based CDC pipeline using Debezium, ksqlDB, and JDBC Sink Connector.

## ❌ Original Problem

The pipeline was failing to handle DELETE operations correctly due to tombstone messages:

**Issue**: When Debezium captures a DELETE from SQL Server, it sends:
1. **DELETE event**: `key={id: 123}`, `value={...fields..., __deleted: true}`
2. **Tombstone**: `key={id: 123}`, `value=null`

**Problem with STREAM approach**:
- KSQL STREAM with `PARTITION BY id` doesn't preserve tombstones correctly
- Tombstone messages get corrupted or lost during transformation
- Sink connector fails when `delete.enabled=true` and `pk.mode=record_key`
- Error: Cannot extract primary key from null value

## ✅ Solution: Use KSQL TABLE

### Why TABLE Instead of STREAM?

| Aspect | STREAM (Old) | TABLE (New) |
|--------|-------------|-------------|
| **Semantics** | Append-only events | Changelog with current state |
| **Primary Key** | No concept | Has primary key |
| **Tombstone Handling** | ❌ Breaks with PARTITION BY | ✅ Preserves correctly |
| **DELETE Support** | ❌ Lost during transformation | ✅ Properly propagated |
| **Log Compaction** | ❌ Not designed for it | ✅ Fully supported |
| **State Management** | Stateless | Stateful (RocksDB on disk) |
| **Queryable** | Only streaming queries | Current state + streaming |

### Changes Made

**File**: `ksql-transformations/01-movies-transform.sql`

**Before (STREAM)**:
```sql
CREATE STREAM movies_source WITH (
    KAFKA_TOPIC='mssql.MoviesDB.cso.movies',
    VALUE_FORMAT='AVRO'
);

CREATE STREAM movies_transformed AS
SELECT * FROM movies_source
PARTITION BY id  -- ❌ Breaks tombstones!
EMIT CHANGES;
```

**After (TABLE)**:
```sql
CREATE TABLE movies_source WITH (
    KAFKA_TOPIC='mssql.MoviesDB.cso.movies',
    KEY_FORMAT='AVRO',
    VALUE_FORMAT='AVRO'
);

CREATE TABLE movies_transformed AS
SELECT * FROM movies_source  -- ✅ Preserves tombstones!
EMIT CHANGES;
```

### Key Improvements

1. **Tombstone Preservation**: TABLEs maintain keys and properly propagate tombstones
2. **CDC Semantics**: TABLEs are designed for changelog data (INSERT, UPDATE, DELETE)
3. **Log Compaction Support**: Compatible with `cleanup.policy=compact` (e.g., Azure Event Hub)
4. **Queryable State**: Can query current state with pull queries
5. **State Recovery**: Automatically rebuilds from Kafka topic if state lost

## 🧠 State Management

### How TABLE State Works

```
┌─────────────────────────────────┐
│   Kafka Topic (Source of Truth) │
│   - All CDC events stored       │
│   - INSERT, UPDATE, DELETE      │
│   - Tombstones for compaction   │
└────────────┬────────────────────┘
             │ Read & Replay
             ▼
┌─────────────────────────────────┐
│   ksqlDB TABLE State Store      │
│   - RocksDB (disk-based)        │
│   - Current state per key       │
│   - NOT all messages            │
└─────────────────────────────────┘
```

### State Size Calculation

- **Storage**: Disk-based (RocksDB), not in-memory
- **Size**: Proportional to **unique keys**, not message count
- **Example**: 
  - 10 million CDC events
  - 1 million unique movie IDs
  - State store: ~1 million records (~1-2 GB on disk)

### State Recovery

If ksqlDB loses its state (crash, corruption, restart):

1. ksqlDB detects missing/corrupt state
2. Reads backing Kafka topic from offset 0
3. Replays all messages (INSERT, UPDATE, DELETE)
4. Rebuilds RocksDB state store
5. Restores exact current state

**No data loss** - Kafka topic is the source of truth!

## 🔬 Testing DELETE Operations

### Prerequisites

```bash
# Ensure all services are running
docker-compose up -d

# Initialize databases
docker exec -it mssql-source /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'TempSA_Password123!' -C -i /init-db-sql/00-create-movies-db.sql

# Populate source database
./populate-source-db.sh

# Start connectors and transformations
./start-source-connector.sh
./apply-ksql-transformations.sh
./start-sink-connector.sh
```

### Test DELETE Tombstone Handling

#### 1. Verify Initial State

```bash
# Check source database
docker exec -it mssql-source /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'TempSA_Password123!' -C -d MoviesDB -Q "SELECT COUNT(*) as count FROM cso.movies"

# Check sink database
docker exec -it mssql-target /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'TempSA_Password123!' -C -d MoviesDB -Q "SELECT COUNT(*) as count FROM cso.movies_sink"
```

Both should show the same count (e.g., 10 movies).

#### 2. Delete a Record from Source

```bash
# Delete a specific movie (e.g., id=1)
docker exec -it mssql-source /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'TempSA_Password123!' -C -d MoviesDB -Q "DELETE FROM cso.movies WHERE id = 1"
```

#### 3. Verify DELETE Event in Kafka

```bash
# Check the transformed topic for DELETE event
docker exec -it kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic mssql.MoviesDB.cso.movies_transformed \
  --from-beginning \
  --max-messages 20 \
  --property print.key=true \
  --property print.value=true
```

You should see:
- **DELETE event**: Key + Value with `__deleted: true`
- **Tombstone**: Key + null value

#### 4. Verify DELETE in Sink Database

```bash
# Wait a few seconds for propagation, then check sink
docker exec -it mssql-target /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'TempSA_Password123!' -C -d MoviesDB -Q "SELECT * FROM cso.movies_sink WHERE id = 1"

# Should return no rows (record deleted)
```

#### 5. Query ksqlDB TABLE State

```bash
# Connect to ksqlDB CLI
docker exec -it ksqldb-cli ksql http://ksqldb-server:8088

# Query current state (pull query)
SELECT * FROM movies_transformed WHERE id = 1;
-- Should return no rows (deleted)

# Count total movies
SELECT COUNT(*) as total FROM movies_transformed;
-- Should be 1 less than original count
```

### Test INSERT After DELETE

```bash
# Re-insert the deleted movie
docker exec -it mssql-source /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'TempSA_Password123!' -C -d MoviesDB -Q "INSERT INTO cso.movies (title, director, release_year, genre) VALUES ('Test Movie', 'Test Director', 2024, 'Drama')"

# Verify in sink (should appear)
docker exec -it mssql-target /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'TempSA_Password123!' -C -d MoviesDB -Q "SELECT * FROM cso.movies_sink WHERE title = 'Test Movie'"
```

## 🔧 Configuration Reference

### Debezium Source Connector

```json
{
  "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
  "transforms.unwrap.drop.tombstones": "false",  // Keep tombstones!
  "transforms.unwrap.delete.handling.mode": "rewrite"  // Add __deleted field
}
```

### JDBC Sink Connector

```json
{
  "delete.enabled": "true",  // Enable DELETE handling
  "pk.mode": "record_key",  // Use message key as primary key
  "insert.mode": "upsert",  // Support INSERT and UPDATE
  "behavior.on.null.values": "ignore"  // Ignore tombstones gracefully
}
```

### ksqlDB TABLE

```sql
CREATE TABLE movies_transformed WITH (
    KEY_FORMAT='AVRO',  // Must match source key format
    VALUE_FORMAT='AVRO'
) AS SELECT * FROM movies_source;
```

## 📊 Monitoring and Troubleshooting

### Check Connector Status

```bash
# Source connector
curl http://localhost:8083/connectors/mssql-source-connector/status | jq

# Sink connector
curl http://localhost:8084/connectors/mssql-sink-connector/status | jq
```

### View Connector Logs

```bash
# Source connector logs
docker logs -f kafka-connect-source

# Sink connector logs
docker logs -f kafka-connect-sink

# ksqlDB logs
docker logs -f ksqldb-server
```

### Common Issues

#### Issue: Tombstone causes sink connector to fail

**Cause**: STREAM with PARTITION BY breaks tombstone key structure

**Solution**: Use TABLE (already implemented)

#### Issue: DELETE not propagating to sink

**Symptoms**:
- Record deleted in source but still exists in sink

**Troubleshooting**:
```bash
# Check if DELETE event in Kafka topic
docker exec -it kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic mssql.MoviesDB.cso.movies_transformed \
  --property print.key=true \
  --property print.value=true

# Check sink connector config
curl http://localhost:8084/connectors/mssql-sink-connector/config | jq

# Verify delete.enabled=true
```

#### Issue: ksqlDB state store corruption

**Solution**: State automatically recovers from Kafka topic
```bash
# Restart ksqlDB (will rebuild state)
docker-compose restart ksqldb-server

# Monitor state recovery in logs
docker logs -f ksqldb-server
```

## 🚀 Production Considerations

### Log Compaction (Azure Event Hub / Kafka)

If using `cleanup.policy=compact`:

1. **Tombstones are essential** - Don't drop them!
2. **TABLE is required** - STREAM doesn't support compaction semantics
3. **Configure retention**: Set `delete.retention.ms` appropriately
4. **Monitor compaction**: Check topic size and message count

### Scaling Considerations

**ksqlDB TABLE State Store**:
- Size: ~1-2 KB per unique key
- 1 million keys ≈ 1-2 GB disk space
- 10 million keys ≈ 10-20 GB disk space
- 100 million keys ≈ 100-200 GB disk space

**Recommendations**:
- Provision adequate disk space for ksqlDB server
- Monitor RocksDB state store size
- Use SSDs for better performance
- Consider partitioning for > 100M keys

### High Availability

**ksqlDB Cluster**:
- State store is local to each instance
- Kafka topic is the source of truth
- Standby instances rebuild state from topic
- No shared state between instances

**Recovery Time**:
- Depends on topic size and message count
- ~100K messages/sec replay speed (typical)
- 10M messages ≈ 100 seconds recovery

## 📚 Additional Resources

- [Debezium SQL Server Connector](https://debezium.io/documentation/reference/stable/connectors/sqlserver.html)
- [ksqlDB TABLE Documentation](https://docs.ksqldb.io/en/latest/concepts/tables/)
- [Confluent JDBC Sink Connector](https://docs.confluent.io/kafka-connect-jdbc/current/sink-connector/index.html)
- [Kafka Log Compaction](https://kafka.apache.org/documentation/#compaction)

## ✅ Summary

**Problem**: STREAM with PARTITION BY breaks DELETE tombstones
**Solution**: Use TABLE for proper CDC changelog semantics
**Benefits**:
- ✅ Proper INSERT, UPDATE, DELETE support
- ✅ Tombstone preservation for log compaction
- ✅ Queryable current state
- ✅ Automatic state recovery
- ✅ Compatible with Azure Event Hub (cleanup.policy=compact)

**No significant downsides**: State store is disk-based and scales to millions of unique keys.
