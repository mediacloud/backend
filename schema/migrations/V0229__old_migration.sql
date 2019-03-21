


-- Helper to find corrupted sequences (the ones in which the primary key's sequence value > MAX(primary_key))
CREATE OR REPLACE FUNCTION find_corrupted_sequences()
RETURNS TABLE(tablename VARCHAR, maxid BIGINT, sequenceval BIGINT)
AS $BODY$
DECLARE
    r RECORD;
BEGIN

    SET client_min_messages TO WARNING;
    DROP TABLE IF EXISTS temp_corrupted_sequences;
    CREATE TEMPORARY TABLE temp_corrupted_sequences (
        tablename VARCHAR NOT NULL UNIQUE,
        maxid BIGINT,
        sequenceval BIGINT
    ) ON COMMIT DROP;
    SET client_min_messages TO NOTICE;

    FOR r IN (

        -- Get all tables, their primary keys and serial sequence names
        SELECT t.relname AS tablename,
               primarykey AS idcolumn,
               pg_get_serial_sequence(t.relname, primarykey) AS serialsequence
        FROM pg_constraint AS c
            JOIN pg_class AS t ON c.conrelid = t.oid
            JOIN pg_namespace nsp ON nsp.oid = t.relnamespace
            JOIN (
                SELECT a.attname AS primarykey,
                       i.indrelid
                FROM pg_index AS i
                    JOIN pg_attribute AS a
                        ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
                WHERE i.indisprimary
            ) AS pkey ON pkey.indrelid = t.relname::regclass
        WHERE conname LIKE '%_pkey'
          AND nsp.nspname = 'public'
          AND t.relname NOT IN (
            'story_similarities_100_short',
            'url_discovery_counts'
          )
        ORDER BY t.relname

    )
    LOOP

        -- Filter out the tables that have their max ID bigger than the last
        -- sequence value
        EXECUTE '
            INSERT INTO temp_corrupted_sequences
                SELECT tablename,
                       maxid,
                       sequenceval
                FROM (
                    SELECT ''' || r.tablename || ''' AS tablename,
                           MAX(' || r.idcolumn || ') AS maxid,
                           ( SELECT last_value FROM ' || r.serialsequence || ') AS sequenceval
                    FROM ' || r.tablename || '
                ) AS id_and_sequence
                WHERE maxid > sequenceval
        ';

    END LOOP;

    RETURN QUERY SELECT * FROM temp_corrupted_sequences ORDER BY tablename;

END
$BODY$
LANGUAGE 'plpgsql';



