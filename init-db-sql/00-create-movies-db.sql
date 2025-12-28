-- =====================================================
-- Source Database Initialization Script
-- Creates MoviesDB database and schema
-- =====================================================

-- Check if database exists, if not create it
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'MoviesDB')
BEGIN
    CREATE DATABASE MoviesDB;
    PRINT 'Database MoviesDB created successfully';
END
ELSE
BEGIN
    PRINT 'Database MoviesDB already exists';
END
GO

-- Switch to the database
USE MoviesDB;
GO

-- Create cso schema if it doesn't exist
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'cso')
BEGIN
    EXEC('CREATE SCHEMA cso');
    PRINT 'Schema cso created successfully';
END
ELSE
BEGIN
    PRINT 'Schema cso already exists';
END
GO

-- Create debezium user for CDC operations
USE master;
GO

-- Create login for debezium user
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'debezium_user')
BEGIN
    CREATE LOGIN debezium_user WITH PASSWORD = 'DebeziumPassword123!';
    PRINT 'Login debezium_user created';
END
ELSE
BEGIN
    PRINT 'Login debezium_user already exists';
END
GO

-- Switch to MoviesDB database
USE MoviesDB;
GO

-- Create user in the database
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'debezium_user')
BEGIN
    CREATE USER debezium_user FOR LOGIN debezium_user;
    PRINT 'User debezium_user created';
END
ELSE
BEGIN
    PRINT 'User debezium_user already exists';
END
GO

-- Grant necessary permissions for CDC operations
ALTER ROLE db_owner ADD MEMBER debezium_user;
GO

-- Grant additional CDC-specific permissions
GRANT VIEW SERVER STATE TO debezium_user;
GO

-- Create movies table if it doesn't exist
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'movies' AND schema_id = SCHEMA_ID('cso'))
BEGIN
    CREATE TABLE cso.movies (
        id INT IDENTITY(1,1) PRIMARY KEY,
        title NVARCHAR(255) NOT NULL,
        director NVARCHAR(255),
        release_year INT,
        genre NVARCHAR(100),
        rating DECIMAL(3,1),
        duration_minutes INT,
        budget BIGINT,
        box_office BIGINT,
        description NVARCHAR(MAX),
        created_at DATETIME2 DEFAULT GETDATE(),
        updated_at DATETIME2 DEFAULT GETDATE()
    );
    PRINT 'Table cso.movies created';
END
ELSE
BEGIN
    PRINT 'Table cso.movies already exists';
END
GO

PRINT 'Source database initialization complete!';
GO

-- Enable CDC on the database
IF (SELECT is_cdc_enabled FROM sys.databases WHERE name = 'MoviesDB') = 0
BEGIN
    PRINT 'Enabling CDC on database...';
    EXEC sys.sp_cdc_enable_db;
    PRINT 'CDC enabled on database';
END
ELSE
BEGIN
    PRINT 'CDC already enabled on database';
END
GO

-- Enable CDC on movies table if not already enabled
IF NOT EXISTS (SELECT * FROM cdc.change_tables WHERE source_object_id = OBJECT_ID('cso.movies'))
BEGIN
    PRINT 'Enabling CDC on movies table...';
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'cso',
        @source_name = N'movies',
        @role_name = NULL,
        @supports_net_changes = 1;
    PRINT 'CDC enabled on movies table';
END
ELSE
BEGIN
    PRINT 'CDC already enabled on movies table';
END
GO

PRINT 'CDC setup completed for MoviesDB!';
GO
