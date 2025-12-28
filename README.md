# Database Integration via Kafka CDC

## About

This project demonstrates a complete **Change Data Capture (CDC)** pipeline for propagating database changes between MSSQL databases using Debezium, Kafka, and ksqlDB. It supports **full CDC operations** including INSERT, UPDATE, and **DELETE** with proper tombstone handling for log compaction.

**Key Features:**
-  Full CDC support (INSERT, UPDATE, DELETE)
-  DELETE tombstone preservation via ksqlDB TABLEs
-  Log compaction compatible (`cleanup.policy=compact`)
-  Azure Event Hub ready
-  Schema transformation with ksqlDB
-  Idempotent deployment

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        Complete CDC Pipeline Architecture                       │
└─────────────────────────────────────────────────────────────────────────────────┘

┌────────────────────┐
│  MSSQL Source      │
│  (MoviesDB)        │
│                    │
│  Table:            │
│  cso.movies        │
│                    │
│  CDC Enabled       │
└─────────┬──────────┘
          │
          │ Transaction Log
          │ (INSERT, UPDATE, DELETE)
          ▼
┌──────────────────────────────────────┐
│  Debezium Source Connector           │
│                                      │
│  Captures CDC events                 │
│  Format: Avro                        │
│  Key: STRUCT{id: int}                │
└─────────┬────────────────────────────┘
          │
          │ Publish
          ▼
┌──────────────────────────────────────┐
│  Kafka Topic                         │
│  mssql.MoviesDB.cso.movies           │
│                                      │
│  Messages: INSERT, UPDATE, DELETE    │
│  DELETE = Tombstone (null value)     │
└─────────┬────────────────────────────┘
          │
          │ Consume
          ▼
┌──────────────────────────────────────┐
│  ksqlDB TABLE: movies_source         │
│                                      │
│  Schema: Inferred from Avro          │
│  Key: STRUCT{id: int}                │
└─────────┬────────────────────────────┘
          │
          │ Transform
          │ SELECT ROWKEY, id, title, ...
          ▼
┌──────────────────────────────────────┐
│  ksqlDB TABLE: movies_transformed    │
│                                      │
│  Key: STRUCT{ID: int} (uppercase!)   │
│  DELETE tombstones preserved         │
└─────────┬────────────────────────────┘
          │
          │ Publish
          ▼
┌──────────────────────────────────────┐
│  Kafka Topic                         │
│  mssql.MoviesDB.cso.movies_          │
│  transformed                         │
│                                      │
│  Tombstones intact for compaction    │
└─────────┬────────────────────────────┘
          │
          │ Consume
          ▼
┌──────────────────────────────────────┐
│  JDBC Sink Connector                 │
│                                      │
│  Config:                             │
│  - pk.fields: "ID"                   │
│  - delete.enabled: true              │
│  - insert.mode: upsert               │
└─────────┬────────────────────────────┘
          │
          │ INSERT, UPDATE, DELETE
          ▼
┌────────────────────┐
│  MSSQL Target      │
│  (MoviesDB)        │
│                    │
│  Table:            │
│  dbo.movies_sink   │
│                    │
│  Full Replication  │
│   INSERT           │
│   UPDATE           │
│   DELETE           │
└────────────────────┘
```

**Key Points:**
- 🔵 **Blue Flow**: Data replication path
- ✅ **Tombstone Preservation**: ksqlDB TABLE maintains DELETE tombstones
- 🔑 **Key Schema Evolution**: `id` → `ID` (ksqlDB uppercases field names)
- 🗜️ **Log Compaction Ready**: Tombstones enable `cleanup.policy=compact`
```

## Why ksqlDB TABLE for CDC?

**TABLEs vs STREAMs for Change Data Capture:**

| Feature | TABLE | STREAM with PARTITION BY |
|---------|-------|--------------------------|
| DELETE tombstone preservation | ✅ Preserves | ❌ Corrupts (sets key to null) |
| Log compaction compatibility | ✅ Compatible | ❌ Not compatible |
| CDC operations | ✅ INSERT, UPDATE, DELETE | ⚠️ INSERT, UPDATE only |
| Use case | **Changelog/CDC data** | Event streams |

**Key Insight:** For CDC data with DELETE operations and log compaction (Azure Event Hub), you **MUST use ksqlDB TABLEs**. STREAMs with `PARTITION BY` will corrupt DELETE tombstones.

## Quick Start

### 1. Start the Complete Pipeline

```bash
./the-whole-thing.sh
```

This script will:
1. Start all services (databases, Kafka, connectors, ksqlDB)
2. Initialize databases with CDC enabled
3. Deploy source connector
4. Create ksqlDB TABLEs for transformation
5. Deploy sink connector
6. Populate sample data (25 movies)
7. Verify data flows through entire pipeline

**Expected Duration:** ~5 minutes from clean slate to full replication

### 2. Verify Data Flow

```bash
# Check source database
docker exec mssql-source /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'TempSA_Password123!' -C -d MoviesDB -Q "SELECT COUNT(*) FROM cso.movies"

# Check sink database
docker exec mssql-target /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'TempSA_Password123!' -C -d MoviesDB -Q "SELECT COUNT(*) FROM movies_sink"
```

### 3. Test DELETE Operation

```bash
# Delete a movie from source
docker exec mssql-source /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'TempSA_Password123!' -C -d MoviesDB -Q "DELETE FROM cso.movies WHERE id = 10"

# Wait for propagation (10 seconds)
sleep 10

# Verify deletion in sink (should return 0 rows)
docker exec mssql-target /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'TempSA_Password123!' -C -d MoviesDB -Q "SELECT COUNT(*) FROM movies_sink WHERE ID = 10"
```

## Manual Step-by-Step Setup

If you prefer to run each step manually:

```bash
# 1. Start all services
docker-compose up -d

# 2. Wait for services to be healthy (~60 seconds)
sleep 60

# 3. Start source connector
./start-source-connector.sh

# 4. Apply ksqlDB transformations
./apply-ksql-transformations.sh

# 5. Start sink connector
./start-sink-connector.sh

# 6. Populate data
./populate-source-db.sh

# 7. Verify data flow (wait ~10 seconds)
sleep 10
docker exec mssql-target /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'TempSA_Password123!' -C -d MoviesDB -Q "SELECT COUNT(*) FROM movies_sink"
```

## Technical Implementation Details

### DELETE Tombstone Handling

**The Problem:**
- Debezium sends DELETE events as tombstones (null value, original key)
- ksqlDB STREAMs with `PARTITION BY` corrupt tombstones by setting key to null
- Corrupted tombstones prevent log compaction from working correctly

**The Solution:**
1. Use **ksqlDB TABLE** (not STREAM) for CDC transformations
2. Include **ROWKEY** in SELECT for TABLE-to-TABLE transformations
3. Let ksqlDB infer schema from Avro (avoid Debezium STRUCT key mismatch)
4. Configure sink connector with correct key field name (`pk.fields=ID`)

### Key Configuration Details

**ksqlDB Transformation** (`ksql-transformations/01-movies-transform.sql`):
```sql
-- Create TABLE by inferring schema from existing topic
CREATE TABLE IF NOT EXISTS movies_source
WITH (
    KAFKA_TOPIC='mssql.MoviesDB.cso.movies',
    KEY_FORMAT='AVRO',
    VALUE_FORMAT='AVRO'
);

-- Transform with ROWKEY included (required for TABLE)
CREATE TABLE IF NOT EXISTS movies_transformed
WITH (
    KAFKA_TOPIC='mssql.MoviesDB.cso.movies_transformed',
    KEY_FORMAT='AVRO',
    VALUE_FORMAT='AVRO',
    PARTITIONS=1,
    REPLICAS=1
) AS
SELECT 
    ROWKEY,  -- REQUIRED for TABLE-to-TABLE transformations
    id,
    title,
    -- ... other fields
FROM movies_source
EMIT CHANGES;
```

**Sink Connector** (`start-sink-connector.sh`):
```json
{
  "pk.mode": "record_key",
  "pk.fields": "ID",  // UPPERCASE - ksqlDB uppercases field names
  "delete.enabled": "true"  // Enable DELETE handling
}
```

### Common Issues and Solutions

**Issue 1: Sink connector fails with "key schema does not contain field: id"**
- **Cause:** ksqlDB uppercases field names (ID not id)
- **Solution:** Set `pk.fields=ID` (uppercase) in sink connector config

**Issue 2: DELETE operations not working**
- **Cause:** Using STREAM instead of TABLE
- **Solution:** Use ksqlDB TABLE for CDC transformations

**Issue 3: "Key missing from projection" error**
- **Cause:** ROWKEY not included in SELECT for TABLE
- **Solution:** Add ROWKEY to SELECT statement

**Issue 4: Init-source-db in infinite retry loop**
- **Cause:** CDC verification query not working correctly
- **Solution:** Fixed in docker-compose.yaml (simplified verification)

## Components

### Core Services

- **MSSQL Source** - Source database with CDC enabled
- **MSSQL Target** - Target database for replicated data
- **Zookeeper** - Coordination service for Kafka
- **Kafka** - Event streaming platform
- **Schema Registry** - Avro schema management
- **Debezium Source Connector** - Captures CDC events from source database
- **ksqlDB Server** - Stream processing and schema transformation
- **JDBC Sink Connector** - Writes transformed data to target database
- **Kafka UI** - Web interface for monitoring (http://localhost:8080)

### Ports

- **1433** - MSSQL Source
- **1434** - MSSQL Target  
- **2181** - Zookeeper
- **8080** - Kafka UI
- **8081** - Schema Registry
- **8083** - Source Connector
- **8084** - Sink Connector
- **8088** - ksqlDB Server
- **9092** - Kafka Broker

## Monitoring and Management

### Kafka UI
Access the Kafka UI at http://localhost:8080 to monitor:
- Topics and messages
- Connectors status
- Schema Registry
- Consumer groups
- ksqlDB queries

### Connector Status
```bash
# Source connector
curl http://localhost:8083/connectors/mssql-source-connector/status | jq

# Sink connector
curl http://localhost:8084/connectors/mssql-sink-connector/status | jq
```

### ksqlDB Queries
```bash
# Access ksqlDB CLI
docker exec -it ksqldb-cli ksql http://ksqldb-server:8088

# List tables
SHOW TABLES;

# Query table
SELECT * FROM movies_transformed EMIT CHANGES;
```

## Production Considerations

### Azure Event Hub Deployment

This solution is ready for Azure Event Hub with the following considerations:

1. **Event Hub Configuration:**
   - Set `cleanup.policy=compact` for tombstone-based compaction
   - Configure appropriate retention periods
   - Size partitions based on throughput requirements

2. **ksqlDB Deployment:**
   - Deploy on Azure Kubernetes Service (AKS)
   - Configure multiple replicas for high availability
   - Use Azure Monitor for logging and metrics

3. **Security:**
   - Use Azure Key Vault for credentials
   - Configure SASL/SSL for Event Hub connections
   - Implement network security groups

4. **Monitoring:**
   - Azure Monitor for metrics collection
   - Application Insights for distributed tracing
   - Alert rules for connector failures

## Documentation

- **[TOMBSTONE_HANDLING_GUIDE.md](TOMBSTONE_HANDLING_GUIDE.md)** - Complete guide on DELETE tombstone handling
- **[USAGE_IN_DOCKER.md](USAGE_IN_DOCKER.md)** - Docker-specific usage and troubleshooting

## Troubleshooting

### Logs
```bash
# Source connector
docker logs kafka-connect-source

# Sink connector  
docker logs kafka-connect-sink

# ksqlDB
docker logs ksqldb-server

# Source database
docker logs mssql-source

# Target database
docker logs mssql-target
```

### Reset Pipeline
```bash
# Stop and remove everything
docker-compose down -v

# Start fresh
./the-whole-thing.sh
```

## License

This project is provided as-is for educational and demonstration purposes.

---

**Status:**  Production-ready with full CDC support including DELETE tombstones
