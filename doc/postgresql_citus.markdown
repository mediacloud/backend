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
