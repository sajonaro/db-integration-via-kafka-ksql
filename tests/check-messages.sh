#!/bin/bash

docker exec -it kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic mssql.MoviesDB.cso.movies --from-beginning --max-messages 2