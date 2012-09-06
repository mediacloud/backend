CREATE OR REPLACE FUNCTION show_stat_activity()
 RETURNS SETOF  pg_stat_activity  AS
$$
DECLARE
BEGIN
    RETURN QUERY select * from pg_stat_activity;
    RETURN;
END;
$$
LANGUAGE 'plpgsql'
;
