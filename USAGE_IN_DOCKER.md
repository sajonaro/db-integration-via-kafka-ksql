# Start all services
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f

# Access services:
# - MSSQL Source: localhost:1433
# - MSSQL Target: localhost:1434
# - Kafka: localhost:9092
# - Source Connector API: localhost:8083
# - Sink Connector API: localhost:8084
# - Kafka UI: http://localhost:8080

# Stop all services
docker-compose down

# Stop and remove volumes (clean start)
docker-compose down -v
