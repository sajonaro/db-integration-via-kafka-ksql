#!/bin/bash

echo "=========================================="
echo "Starting Complete Pipeline"
echo "=========================================="

# 1. Restart all services with new configuration
echo "Step 1: Restarting all services..."
docker-compose down -v
docker-compose up -d

# 2. Wait for all services to be healthy
echo ""
echo "Step 2: Waiting for services to be healthy (90 seconds)..."
sleep 90
docker-compose ps

# 3. Start the source connector (with Avro)
echo ""
echo "Step 3: Starting source connector..."
./start-source-connector.sh

# 4. Insert ONE dummy record to trigger schema registration (will be deleted later)
echo ""
echo "Step 4: Inserting dummy record to register schema..."
docker exec -it mssql-source /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'TempSA_Password123!' -C -d MoviesDB -Q "INSERT INTO cso.movies (title, director, release_year, genre, duration_minutes) VALUES ('DUMMY', 'DUMMY', 1900, 'DUMMY', 1)"

# 5. Wait for schema to be registered in Schema Registry
echo ""
echo "Step 5: Waiting for schema to be registered (15 seconds)..."
sleep 15

# Verify schema is registered
echo "Verifying schema registration..."
SCHEMA_COUNT=$(curl -s http://localhost:8081/subjects | grep -c "mssql.MoviesDB.cso.movies-value" || echo "0")
if [ "$SCHEMA_COUNT" -eq "0" ]; then
    echo "⚠️  Schema not yet registered, waiting another 10 seconds..."
    sleep 10
fi
echo "✅ Schema registered"

# 6. NOW apply KSQL transformations (schema exists now, TABLE will process all future data)
echo ""
echo "Step 6: Applying KSQL transformations (creating TABLEs for CDC)..."
./apply-ksql-transformations.sh

# 7. Delete the dummy record (TABLE will process this DELETE with tombstone)
echo ""
echo "Step 7: Deleting dummy record (testing DELETE tombstone handling)..."
docker exec -it mssql-source /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'TempSA_Password123!' -C -d MoviesDB -Q "DELETE FROM cso.movies WHERE title='DUMMY'"

# 8. NOW populate the database (KSQL TABLE already exists, will process all 25 records!)
echo ""
echo "Step 8: Populating source database (KSQL TABLE is ready to process)..."
./populate-source-db.sh

# Wait for KSQL to start processing
echo "Waiting for KSQL TABLE transformation to initialize (10 seconds)..."
sleep 10

# Verify KSQL query is running
echo "Verifying KSQL TABLE transformation is running..."
KSQL_QUERY_COUNT=$(curl -s -X POST http://localhost:8088/ksql -H 'Content-Type: application/vnd.ksql.v1+json' -d '{"ksql":"SHOW QUERIES;"}' | grep -c '"state":"RUNNING"' || echo "0")
echo "Found $KSQL_QUERY_COUNT running KSQL queries"

if [ "$KSQL_QUERY_COUNT" -eq "0" ]; then
    echo "❌ CRITICAL ERROR: KSQL transformation failed to apply!"
    echo "Check: docker logs ksqldb-server"
    exit 1
fi
echo "✅ KSQL transformation verified running ($KSQL_QUERY_COUNT queries)"

# 9. Start the sink connector (with Avro)
echo ""
echo "Step 9: Starting sink connector..."
./start-sink-connector.sh

# 10. Verify schemas are registered
echo ""
echo "Step 10: Checking registered schemas..."
curl -s http://localhost:8081/subjects | python3 -m json.tool

# Wait for data to flow through pipeline (all 25 movies)
echo "Waiting for data to flow through pipeline (30 seconds)..."
sleep 30

# 11. Verify data counts
echo ""
echo "Step 11: Verifying data flow..."
echo "Source topic messages:"
docker exec kafka kafka-run-class kafka.tools.GetOffsetShell --broker-list localhost:9092 --topic mssql.MoviesDB.cso.movies 2>/dev/null | awk -F: '{sum+=$3} END {print sum}'
echo ""
echo "Transformed topic messages:"
docker exec kafka kafka-run-class kafka.tools.GetOffsetShell --broker-list localhost:9092 --topic mssql.MoviesDB.cso.movies_transformed 2>/dev/null | awk -F: '{sum+=$3} END {print sum}'

# 12. Check data in target database (correct table name: dbo.movies_sink)
echo ""
echo "Step 12: Checking target database..."
docker exec -it mssql-target /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'TempSA_Password123!' -C -d MoviesDB -Q 'SELECT COUNT(*) AS RecordCount FROM dbo.movies_sink'

echo ""
echo "=========================================="
echo "Pipeline Complete!"
echo "=========================================="
