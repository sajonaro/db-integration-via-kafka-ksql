#!/bin/bash

echo "Initializing Debezium Source Connector for MSSQL..."
echo ""

# Navigate to the script directory
cd "$(dirname "$0")"

# Check if Kafka Connect is running
echo "Checking if Kafka Connect (source-connector) is running..."
if ! docker ps | grep -q "kafka-connect-source"; then
    echo "❌ Error: Kafka Connect source container is not running!"
    echo "Please start it first by running: docker-compose up -d"
    exit 1
fi

# Wait for Kafka Connect to be ready
echo "Waiting for Kafka Connect to be ready..."
MAX_WAIT=60
COUNTER=0
until curl -s http://localhost:8083/ > /dev/null 2>&1; do
    sleep 2
    COUNTER=$((COUNTER + 2))
    if [ $COUNTER -ge $MAX_WAIT ]; then
        echo "❌ Kafka Connect did not start within ${MAX_WAIT} seconds"
        exit 1
    fi
    echo "  Waiting... ($COUNTER/$MAX_WAIT seconds)"
done

echo "✅ Kafka Connect is ready"
echo ""

# Check if MSSQL source is running
echo "Checking if MSSQL source database is running..."
if ! docker ps | grep -q "mssql-source"; then
    echo "❌ Error: MSSQL source container is not running!"
    exit 1
fi

echo "✅ MSSQL source is running"
echo ""

# Check if MoviesDB database exists and CDC is enabled
echo "Verifying CDC is enabled on source database..."
CDC_CHECK=$(docker exec -i mssql-source /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "TempSA_Password123!" -C -d MoviesDB -Q "SET NOCOUNT ON; SELECT is_cdc_enabled FROM sys.databases WHERE name = 'MoviesDB';" -h -1 -W | tr -d '[:space:]')

if [ "$CDC_CHECK" != "1" ]; then
    echo "❌ CDC is not enabled on MoviesDB database!"
    echo "Please run the database initialization script first."
    exit 1
fi

echo "✅ CDC is enabled"
echo ""

# Delete existing connector if it exists
echo "Checking for existing connector..."
EXISTING_CONNECTOR=$(curl -s http://localhost:8083/connectors | grep -o "mssql-source-connector" || true)

if [ -n "$EXISTING_CONNECTOR" ]; then
    echo "Found existing connector. Deleting it..."
    curl -X DELETE http://localhost:8083/connectors/mssql-source-connector
    echo ""
    sleep 2
fi

# Create the connector configuration
echo "Creating Debezium Source Connector configuration..."
cat > /tmp/debezium-source-connector.json << 'EOF'
{
  "name": "mssql-source-connector",
  "config": {
    "connector.class": "io.debezium.connector.sqlserver.SqlServerConnector",
    "tasks.max": "1",
    "database.hostname": "mssql-source",
    "database.port": "1433",
    "database.user": "debezium_user",
    "database.password": "DebeziumPassword123!",
    "database.names": "MoviesDB",
    "database.server.name": "sqlserver",
    "database.encrypt": "false",
    "database.trustServerCertificate": "true",
    "table.include.list": "cso.movies",
    "database.history.kafka.bootstrap.servers": "kafka:29092",
    "database.history.kafka.topic": "schema-changes.sqlserver",
    "schema.history.internal.kafka.bootstrap.servers": "kafka:29092",
    "schema.history.internal.kafka.topic": "schema-changes.sqlserver",
    "include.schema.changes": "true",
    "snapshot.mode": "initial",
    "snapshot.locking.mode": "none",
    "provide.transaction.metadata": "true",
    "transforms": "unwrap",
    "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
    "transforms.unwrap.drop.tombstones": "false",
    "transforms.unwrap.delete.handling.mode": "rewrite",
    "key.converter": "io.confluent.connect.avro.AvroConverter",
    "key.converter.schema.registry.url": "http://schema-registry:8081",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": "http://schema-registry:8081",
    "topic.prefix": "mssql"
  }
}
EOF

echo "✅ Configuration created"
echo ""

# Deploy the connector
echo "Deploying Debezium Source Connector..."
RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  --data @/tmp/debezium-source-connector.json \
  http://localhost:8083/connectors)

if echo "$RESPONSE" | grep -q "error_code"; then
    echo "❌ Failed to create connector!"
    echo "Error: $RESPONSE"
    exit 1
fi

echo "✅ Connector deployed successfully"
echo ""

# Wait a moment for the connector to initialize
echo "Waiting for connector to initialize..."
sleep 5

# Check connector status
echo "Checking connector status..."
STATUS=$(curl -s http://localhost:8083/connectors/mssql-source-connector/status)

echo "$STATUS" | python3 -m json.tool 2>/dev/null || echo "$STATUS"
echo ""

# Check if connector is running
CONNECTOR_STATE=$(echo "$STATUS" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
TASK_STATE=$(echo "$STATUS" | grep -o '"state":"[^"]*"' | tail -1 | cut -d'"' -f4)

if [ "$CONNECTOR_STATE" = "RUNNING" ] && [ "$TASK_STATE" = "RUNNING" ]; then
    echo "✅ Connector is RUNNING successfully!"
else
    echo "⚠️  Connector state: $CONNECTOR_STATE, Task state: $TASK_STATE"
    echo "Check the logs with: docker logs kafka-connect-source"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Source Connector Information"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Connector Name: mssql-source-connector"
echo "Source Database: mssql-source:1433/MoviesDB"
echo "Kafka Bootstrap: kafka:29092"
echo "Schema Registry: http://schema-registry:8081"
echo "Topic Prefix: mssql"
echo "Data Format: Avro with Schema"
echo ""
echo "📝 Monitored Tables:"
echo "  - cso.movies → Topic: mssql.MoviesDB.cso.movies"
echo ""
echo "🔧 Useful Commands:"
echo "  View connector status:"
echo "    curl http://localhost:8083/connectors/mssql-source-connector/status | jq"
echo ""
echo "  List all connectors:"
echo "    curl http://localhost:8083/connectors | jq"
echo ""
echo "  View Kafka topics:"
echo "    docker exec -it kafka kafka-topics --bootstrap-server localhost:9092 --list"
echo ""
echo "  View schemas in Schema Registry:"
echo "    curl http://localhost:8081/subjects | jq"
echo ""
echo "  Delete connector:"
echo "    curl -X DELETE http://localhost:8083/connectors/mssql-source-connector"
echo ""
echo "  View connector logs:"
echo "    docker logs -f kafka-connect-source"
echo ""
echo "  Access Kafka UI:"
echo "    http://localhost:8080"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Clean up
rm -f /tmp/debezium-source-connector.json
