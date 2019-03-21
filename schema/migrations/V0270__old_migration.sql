


CREATE OR REPLACE FUNCTION create_missing_partitions() RETURNS VOID AS
$$
BEGIN
    -- "bitly_clicks_total" table
    RAISE NOTICE 'Creating partitions in "bitly_clicks_total" table...';
    PERFORM bitly_clicks_total_create_partitions();
END;
$$
LANGUAGE plpgsql;


