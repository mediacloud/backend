


-- Create index if it doesn't exist already
--
-- Should be removed after migrating to PostgreSQL 9.5 because it supports
-- CREATE INDEX IF NOT EXISTS natively.
CREATE OR REPLACE FUNCTION create_index_if_not_exists(schema_name TEXT, table_name TEXT, index_name TEXT, index_sql TEXT)
RETURNS void AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM   pg_class c
        JOIN   pg_namespace n ON n.oid = c.relnamespace
        WHERE  c.relname = index_name
        AND    n.nspname = schema_name
    ) THEN
        EXECUTE 'CREATE INDEX ' || index_name || ' ON ' || schema_name || '.' || table_name || ' ' || index_sql;
    END IF;
END
$$
LANGUAGE plpgsql VOLATILE;


