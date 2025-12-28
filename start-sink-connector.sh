#!/bin/bash

echo "Initializing JDBC Sink Connector for MSSQL Target Database..."
echo ""

# Navigate to the script directory
cd "$(dirname "$0")"

# Check if Kafka Connect sink is running
echo "Checking if Kafka Connect (sink-connector) is running..."
if ! docker ps | grep -q "kafka-connect-sink"; then
    echo "❌ Error: Kafka Connect sink container is not running!"
    echo "Please start it first by running: docker-compose up -d sink-connector"
    exit 1
fi

# Wait for Kafka Connect to be ready
echo "Waiting for Kafka Connect sink to be ready..."
MAX_WAIT=60
COUNTER=0
until curl -s http://localhost:8084/ > /dev/null 2>&1; do
    sleep 2
    COUNTER=$((COUNTER + 2))
    if [ $COUNTER -ge $MAX_WAIT ]; then
        echo "❌ Kafka Connect sink did not start within ${MAX_WAIT} seconds"
        exit 1
    fi
    echo "  Waiting... ($COUNTER/$MAX_WAIT seconds)"
done

echo "✅ Kafka Connect sink is ready"
echo ""

# Check if MSSQL target is running
echo "Checking if MSSQL target database is running..."
if ! docker ps | grep -q "mssql-target"; then
    echo "❌ Error: MSSQL target container is not running!"
    exit 1
fi

echo "✅ MSSQL target is running"
echo ""

# Delete existing connector if it exists
echo "Checking for existing sink connector..."
EXISTING_CONNECTOR=$(curl -s http://localhost:8084/connectors | grep -o "mssql-sink-connector" || true)

if [ -n "$EXISTING_CONNECTOR" ]; then
    echo "Found existing connector. Deleting it..."
    curl -X DELETE http://localhost:8084/connectors/mssql-sink-connector
    echo ""
    sleep 2
fi

# Create the connector configuration
echo "Creating JDBC Sink Connector configuration..."
cat > /tmp/mssql-sink-connector.json << 'EOF'
{
  "name": "mssql-sink-connector",
  "config": {
    "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
    "tasks.max": "1",
    "connection.url": "jdbc:sqlserver://mssql-target:1433;databaseName=MoviesDB;encrypt=false;trustServerCertificate=true",
    "connection.user": "sa",
    "connection.password": "TempSA_Password123!",
    "topics": "mssql.MoviesDB.cso.movies_transformed",
    "auto.create": "true",
    "auto.evolve": "true",
    "insert.mode": "upsert",
    "pk.mode": "record_key",
    "pk.fields": "ID",
    "table.name.format": "movies_sink",
    "delete.enabled": "true",
    "key.converter": "io.confluent.connect.avro.AvroConverter",
    "key.converter.schema.registry.url": "http://schema-registry:8081",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": "http://schema-registry:8081",
    "batch.size": 3000,
    "max.retries": 10,
    "retry.backoff.ms": 3000,
    "behavior.on.null.values": "ignore",
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
  }
}
EOF

echo "✅ Configuration created"
echo ""

# Deploy the connector
echo "Deploying JDBC Sink Connector..."
RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  --data @/tmp/mssql-sink-connector.json \
  http://localhost:8084/connectors)

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
STATUS=$(curl -s http://localhost:8084/connectors/mssql-sink-connector/status)

echo "$STATUS" | python3 -m json.tool 2>/dev/null || echo "$STATUS"
echo ""

# Check if connector is running
CONNECTOR_STATE=$(echo "$STATUS" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ "$CONNECTOR_STATE" = "RUNNING" ]; then
    echo "✅ Sink Connector is RUNNING successfully!"
else
    echo "⚠️  Connector state: $CONNECTOR_STATE"
    echo "Check the logs with: docker logs kafka-connect-sink"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Sink Connector Information"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Connector Name: mssql-sink-connector"
echo "Target Database: mssql-target:1433/MoviesDB"
echo "JDBC Driver: SQL Server"
echo "Schema Registry: http://schema-registry:8081"
echo "Data Format: Avro with Schema"
echo ""
echo "📝 Source Topics → Target Tables:"
echo "  - mssql.MoviesDB.cso.movies_transformed"
echo "    → cso.movies_sink"
echo ""
echo "🔧 Useful Commands:"
echo "  View connector status:"
echo "    curl http://localhost:8084/connectors/mssql-sink-connector/status | jq"
echo ""
echo "  List all sink connectors:"
echo "    curl http://localhost:8084/connectors | jq"
echo ""
echo "  Check target database tables:"
echo "    docker exec -it mssql-target /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'TempSA_Password123!' -C -d MoviesDB -Q 'SELECT name FROM sys.tables WHERE name LIKE \"%sink%\"'"
echo ""
echo "  View data in sink table:"
echo "    docker exec -it mssql-target /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'TempSA_Password123!' -C -d MoviesDB -Q 'SELECT TOP 5 * FROM cso.movies_sink'"
echo ""
echo "  View schemas in Schema Registry:"
echo "    curl http://localhost:8081/subjects | jq"
echo ""
echo "  Delete connector:"
echo "    curl -X DELETE http://localhost:8084/connectors/mssql-sink-connector"
echo ""
echo "  View connector logs:"
echo "    docker logs -f kafka-connect-sink"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Clean up
rm -f /tmp/mssql-sink-connector.json
