


-- Upsert helper to INSERT or UPDATE an object to object cache
CREATE OR REPLACE FUNCTION cache.upsert_cache_object (
    param_table_name VARCHAR,
    param_object_id BIGINT,
    param_raw_data BYTEA
) RETURNS VOID AS
$$
DECLARE
    _cache_object_found INT;
BEGIN

    LOOP
        -- Try UPDATing
        EXECUTE '
            UPDATE ' || param_table_name || '
            SET raw_data = $2
            WHERE object_id = $1
            RETURNING *
        ' INTO _cache_object_found
          USING param_object_id, param_raw_data;

        IF _cache_object_found IS NOT NULL THEN RETURN; END IF;

        -- Nothing to UPDATE, try to INSERT a new record
        BEGIN

            EXECUTE '
                INSERT INTO ' || param_table_name || ' (object_id, raw_data)
                VALUES ($1, $2)
            ' USING param_object_id, param_raw_data;

            RETURN;

        EXCEPTION WHEN UNIQUE_VIOLATION THEN
            -- If someone else INSERTs the same key concurrently,
            -- we will get a unique-key failure. In that case, do
            -- nothing and loop to try the UPDATE again.
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql;



