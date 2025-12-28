#!/bin/bash
curl -s -X POST http://localhost:8088/ksql -H "Content-Type: application/vnd.ksql.v1+json" -d '{"ksql":"SHOW QUERIES;"}' | jq