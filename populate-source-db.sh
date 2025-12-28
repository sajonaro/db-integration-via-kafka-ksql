#!/bin/bash

echo "Populating movies table in MoviesDB database..."
echo ""

# Navigate to the script directory
cd "$(dirname "$0")"

# Check if the MSSQL container is running
if ! docker ps | grep -q "mssql-source"; then
    echo "Error: MSSQL container is not running!"
    echo "Please start it first by running: docker-compose up -d"
    exit 1
fi

echo "Waiting for MSSQL to be fully ready..."
sleep 5

# First, check if the database exists and create it if needed
echo "Checking if MoviesDB database exists..."
docker exec -i mssql-source /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "TempSA_Password123!" -C -Q "
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'MoviesDB')
BEGIN
    PRINT 'Database does not exist. Please run initialization first.';
    RAISERROR('MoviesDB database not found. Run init-db-sql/00-create-movies-db.sql first.', 16, 1);
END
ELSE
BEGIN
    PRINT 'Database exists. Proceeding with data population.';
END
"

if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Database not initialized. Initializing now..."
    
    # Copy and run the initialization script
    docker cp init-db-sql/00-create-movies-db.sql mssql-source:/tmp/
    docker exec -i mssql-source /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "TempSA_Password123!" -C -i /tmp/00-create-movies-db.sql
    
    if [ $? -ne 0 ]; then
        echo "❌ Failed to initialize database"
        exit 1
    fi
    
    echo "✅ Database initialized successfully"
    echo ""
fi

echo "Executing SQL script to populate movies table..."
echo ""

# Copy the populate script to the container
docker cp init-db-sql/populate-movies.sql mssql-source:/tmp/

# Execute the SQL script using sqlcmd in the container
docker exec -i mssql-source /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "TempSA_Password123!" -C -i /tmp/populate-movies.sql

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ Movies table populated successfully!"
    echo ""
    
    # Verify the data was inserted
    echo "Verifying data insertion..."
    MOVIE_COUNT=$(docker exec -i mssql-source /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "TempSA_Password123!" -C -d MoviesDB -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM cso.movies;" -h -1 -W | tr -d '[:space:]')
    
    echo "Movies in database: $MOVIE_COUNT"
    echo ""
    echo "You can now query the movies table using:"
    echo "  docker exec -it mssql-source /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'TempSA_Password123!' -C -d MoviesDB"
    echo "  Then run: SELECT * FROM cso.movies;"
    echo ""
    echo "Or connect from your host:"
    echo "  Server: localhost,1433"
    echo "  Database: MoviesDB"
    echo "  Username: sa"
    echo "  Password: TempSA_Password123!"
else
    echo ""
    echo "❌ Error occurred while populating movies table."
    echo "Please check the error messages above."
    exit 1
fi
