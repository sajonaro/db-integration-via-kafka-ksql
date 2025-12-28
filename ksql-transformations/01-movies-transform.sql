-- =====================================================
-- Transformation: Movies Table
-- Source: mssql.MoviesDB.cso.movies
-- Target: mssql.MoviesDB.cso.movies_transformed
-- =====================================================
-- 
-- ARCHITECTURE: Using TABLE for proper CDC handling
-- 
-- Let ksqlDB infer the schema from the existing Avro topic
-- (Debezium's key is a STRUCT, not a simple primitive)
--
-- =====================================================

-- Set to read from beginning to process historical data
SET 'auto.offset.reset' = 'earliest';

-- Create TABLE by inferring schema from existing topic
-- No explicit schema - ksqlDB will use the Avro schema from Schema Registry
CREATE TABLE IF NOT EXISTS movies_source
WITH (
    KAFKA_TOPIC='mssql.MoviesDB.cso.movies',
    KEY_FORMAT='AVRO',
    VALUE_FORMAT='AVRO'
);

-- Create transformed TABLE - include ROWKEY as required by ksqlDB
-- For TABLEs, the key automatically propagates (no PARTITION BY needed/allowed)
CREATE TABLE IF NOT EXISTS movies_transformed
WITH (
    KAFKA_TOPIC='mssql.MoviesDB.cso.movies_transformed',
    KEY_FORMAT='AVRO',
    VALUE_FORMAT='AVRO',
    PARTITIONS=1,
    REPLICAS=1
) AS
SELECT 
    ROWKEY,
    id,
    title,
    director,
    release_year,
    genre,
    rating,
    duration_minutes,
    budget,
    box_office,
    description,
    created_at,
    updated_at,
    __deleted
FROM movies_source
EMIT CHANGES;
