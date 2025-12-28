#!/bin/bash

docker exec -it kafka kafka-topics --bootstrap-server localhost:9092 --list | grep mssql