#!/bin/bash

# Insert a new movie into MSSQL source
docker exec -i mssql-source /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "TempSA_Password123!" -C -d MoviesDB -Q "
INSERT INTO cso.movies (title, director, release_year, genre, rating, duration_minutes, budget, box_office, description) 
VALUES ('Test Movie', 'Test Director', 2024, 'Action', 8.5, 120, 10000000, 50000000, 'This is a test movie to verify ksqlDB transformations');
"

# Wait a few seconds, then check transformed topic
docker exec -it kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic mssql.MoviesDB.cso.movies_transformed --from-beginning --max-messages 1
