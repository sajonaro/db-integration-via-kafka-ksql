#!/bin/bash

echo "========================================="
echo "Applying ksqlDB Transformations"
echo "========================================="
echo ""

# Check if ksqlDB server is running
if ! docker ps | grep -q "ksqldb-server"; then
    echo "❌ Error: ksqlDB server is not running!"
    echo "Please start it first by running: docker-compose up -d ksqldb-server"
    exit 1
fi

# Wait for ksqlDB to be ready
echo "Waiting for ksqlDB server to be ready..."
MAX_WAIT=60
COUNTER=0
until curl -s http://localhost:8088/info > /dev/null 2>&1; do
    sleep 2
    COUNTER=$((COUNTER + 2))
    if [ $COUNTER -ge $MAX_WAIT ]; then
        echo "❌ ksqlDB server did not start within ${MAX_WAIT} seconds"
        exit 1
    fi
    echo "  Waiting... ($COUNTER/$MAX_WAIT seconds)"
done

echo "✅ ksqlDB server is ready!"
echo ""

# Configure KSQL to read from earliest offset (process historical data)
echo "📝 Configuring KSQL to read from earliest offset..."
curl -s -X POST http://localhost:8088/ksql \
    -H "Content-Type: application/vnd.ksql.v1+json" \
    -d '{
        "ksql": "SET '\''auto.offset.reset'\'' = '\''earliest'\'';",
        "streamsProperties": {}
    }' > /dev/null
echo "✅ Configured to read historical data"
echo ""

# Apply transformations in order
for sql_file in $(ls -1 ksql-transformations/*.sql | sort); do
    filename=$(basename "$sql_file")
    echo "📝 Applying: $filename"

    # Read the SQL file and split by semicolons, send each statement separately
    # Remove comments and empty lines, then split on semicolons
    grep -v '^--' "$sql_file" | grep -v '^[[:space:]]*$' | tr '\n' ' ' | sed 's/;/;\n/g' | while IFS= read -r statement; do
        # Skip empty statements
        if [ -z "$(echo "$statement" | tr -d '[:space:]')" ]; then
            continue
        fi
        
        # Add semicolon back if not present
        if ! echo "$statement" | grep -q ';'; then
            statement="${statement};"
        fi
        
        # Create JSON payload for single statement with streamsProperties to read from earliest
        PAYLOAD=$(jq -n --arg sql "$statement" '{
            ksql: $sql,
            streamsProperties: {
                "ksql.streams.auto.offset.reset": "earliest"
            }
        }')
        
        # Send to ksqlDB
        RESPONSE=$(curl -s -X POST http://localhost:8088/ksql \
            -H "Content-Type: application/vnd.ksql.v1+json" \
            -d "$PAYLOAD")
        
        # Check for errors in response
        if echo "$RESPONSE" | grep -q "error_code"; then
            echo "❌ Failed to apply statement"
            echo "Error: $RESPONSE"
        else
            echo "✅ Applied statement successfully"
        fi
        sleep 1
    done
    
    echo "✅ Applied successfully"
    echo ""
    sleep 2
done

echo "========================================="
echo "Transformation Application Complete!"
echo "========================================="
echo ""
echo "📊 Verify transformations:"
echo "  List streams:"
echo "    curl -X POST http://localhost:8088/ksql -H 'Content-Type: application/vnd.ksql.v1+json' -d '{\"ksql\":\"SHOW STREAMS;\"}'"
echo ""
echo "  List topics:"
echo "    docker exec -it kafka kafka-topics --bootstrap-server localhost:9092 --list | grep transformed"
echo ""
echo "  Access ksqlDB CLI:"
echo "    docker exec -it ksqldb-cli ksql http://ksqldb-server:8088"
echo ""
