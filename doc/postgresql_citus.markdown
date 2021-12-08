# PostgreSQL + Citus




## Tips, tricks, notes, gochas


### Triggers have to be recreated on newly added workers


While distributed functions will get propagated to newly added workers, triggers won't, so one will have to recreate them manually, e.g.:

```sql
-- Insert new rows to "media_rescraping" for each new row in "media"
SELECT run_on_shards_or_raise('media', $cmd$

    CREATE TRIGGER media_rescraping_add_initial_state_trigger
        AFTER INSERT
        ON %s
        FOR EACH ROW
    EXECUTE PROCEDURE media_rescraping_add_initial_state_trigger();

    $cmd$);
```


### Temporarily disabling triggers doesn't work

```sql
SET session_replication_role = replica;
```

won't do what you expect, and will probably lead to weird errors such as:

```
2021-12-07 13:39:30 EST [64-1] mediacloud@mediacloud ERROR:  cannot use 2PC in transactions involving multiple servers
2021-12-07 13:39:30 EST [64-2] mediacloud@mediacloud STATEMENT:  PREPARE TRANSACTION 'citus_0_63_89_0'
2021-12-07 13:39:30 EST [63-1] mediacloud@mediacloud ERROR:  cannot use 2PC in transactions involving multiple servers
2021-12-07 13:39:30 EST [63-2] mediacloud@mediacloud CONTEXT:  while executing command on localhost:5432
2021-12-07 13:39:30 EST [63-3] mediacloud@mediacloud STATEMENT:
                WITH deleted_rows AS (
                    DELETE FROM unsharded_public.processed_stories

                    WHERE
                        processed_stories_id BETWEEN 1 AND 50000001

                    RETURNING processed_stories_id, stories_id
                )
                INSERT INTO sharded_public.processed_stories (processed_stories_id, stories_id)
                    SELECT processed_stories_id::BIGINT, stories_id::BIGINT
                    FROM deleted_rows
                ON CONFLICT (stories_id) DO NOTHING
```
