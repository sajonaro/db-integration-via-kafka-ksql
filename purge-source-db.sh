#!/bin/bash

echo "========================================="
echo "Purging CDC-Enabled Tables in Source DB"
echo "========================================="
echo ""

# Navigate to the script directory
cd "$(dirname "$0")"

# Check if the MSSQL container is running
if ! docker ps | grep -q "mssql-source"; then
    echo "❌ Error: MSSQL source container is not running!"
    echo "Please start it first by running: docker-compose up -d"
    exit 1
fi

echo "⚠️  WARNING: This will DELETE all records from the following tables:"
echo "  - cso.movies"
echo "  - cso.DimProduct"
echo "  - cso.DimCustomer"
echo "  - cso.FactSales"
echo ""
echo "This action CANNOT be undone!"
echo ""
echo "Press Ctrl+C to cancel, or Enter to continue..."
read

echo ""
echo "Purging all CDC-enabled tables..."
echo ""

# Execute the DELETE commands for all tables
docker exec -i mssql-source /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "TempSA_Password123!" -C -d MoviesDB << 'EOF'
-- Disable foreign key constraints temporarily
EXEC sp_MSforeachtable "ALTER TABLE ? NOCHECK CONSTRAINT all"
GO

-- Delete from movies table
PRINT '🗑️  Deleting from cso.movies...'
DELETE FROM cso.movies;
PRINT '   Rows deleted: ' + CAST(@@ROWCOUNT AS VARCHAR(10))
PRINT ''
GO

-- Delete from DimProduct table
PRINT '🗑️  Deleting from cso.DimProduct...'
DELETE FROM cso.DimProduct;
PRINT '   Rows deleted: ' + CAST(@@ROWCOUNT AS VARCHAR(10))
PRINT ''
GO

-- Delete from DimCustomer table
PRINT '🗑️  Deleting from cso.DimCustomer...'
DELETE FROM cso.DimCustomer;
PRINT '   Rows deleted: ' + CAST(@@ROWCOUNT AS VARCHAR(10))
PRINT ''
GO

-- Delete from FactSales table
PRINT '🗑️  Deleting from cso.FactSales...'
DELETE FROM cso.FactSales;
PRINT '   Rows deleted: ' + CAST(@@ROWCOUNT AS VARCHAR(10))
PRINT ''
GO

-- Re-enable foreign key constraints
EXEC sp_MSforeachtable "ALTER TABLE ? WITH CHECK CHECK CONSTRAINT all"
GO

-- Show final counts
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT 'Final Record Counts:'
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
GO

SELECT 'movies' AS TableName, COUNT(*) AS RecordCount FROM cso.movies
UNION ALL
SELECT 'DimProduct', COUNT(*) FROM cso.DimProduct
UNION ALL
SELECT 'DimCustomer', COUNT(*) FROM cso.DimCustomer
UNION ALL
SELECT 'FactSales', COUNT(*) FROM cso.FactSales;
GO
EOF

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ All CDC-enabled tables purged successfully!"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Verify Deletion Propagation Through Pipeline:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1️⃣  Check Source Database (should be empty):"
    echo "    docker exec -it mssql-source /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'TempSA_Password123!' -C -d MoviesDB -Q 'SELECT COUNT(*) FROM cso.movies'"
    echo ""
    echo "2️⃣  Monitor Deletion Events in Kafka Source Topics:"
    echo "    docker exec -it kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic mssql.MoviesDB.cso.movies --from-beginning --property print.key=true --max-messages 5"
    echo ""
    echo "3️⃣  Check Deletion in Transformed Topics:"
    echo "    docker exec -it kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic mssql.MoviesDB.cso.movies_transformed --from-beginning --max-messages 5"
    echo ""
    echo "4️⃣  Verify Target Database (check if deletions propagated):"
    echo "    docker exec -it mssql-target /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'TempSA_Password123!' -C -d MoviesDB -Q 'SELECT name FROM sys.tables WHERE schema_name(schema_id) = \"cso\"'"
    echo ""
    echo "5️⃣  Check Kafka UI:"
    echo "    http://localhost:8080"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "💡 Note: CDC capture will process these deletions and send tombstone"
    echo "   records (records with __deleted='true') to Kafka topics."
    echo ""
    echo "To repopulate the data, run: ./populate-source-db.sh"
else
    echo ""
    echo "❌ Error occurred while purging tables."
    echo "Please check the error messages above."
    exit 1
fi
