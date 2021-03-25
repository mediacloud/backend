# Why `temporal-postgresql` is pre-initialized using a SQL dump instead of `temporal-sql-tool`?

In the vendor's Docker image, PostgreSQL's schema gets initialized using `temporal-sql-tool`:

https://github.com/temporalio/temporal/blob/9fcf5e4153b29302de3c2333fdeff6343d0ca889/docker/start.sh#L71-L78

Later, the default namespace gets registered in the background, while `temporal-server` is getting started:

https://github.com/temporalio/temporal/blob/9fcf5e4153b29302de3c2333fdeff6343d0ca889/docker/start.sh#L179-L187

There are a few issues with this approach:

1. Running an important command in background while starting a service is not particularly "clean";
2. Clients can't just wait for `temporal-server`'s port to open because there's no guarantee that the default namespace will already exist when they first connect;
3. Even when `tctl` manages to create the namespace, it doesn't seem to become available to clients for about 30 seconds so the clients are then forced to test for namespace existence.

Therefore, to generate the default schema we:

1. Pre-initialize schema using vendor's tools;
2. Start Temporal server;
3. Create default namespace;
4. Wait for a minute to let things "settle" or whatever it is that it's doing in the background;
5. `pg_dump` both databases to schema files to be later used for building the image.

This is how the initial schema was generated:

```bash
export TSQL="temporal-sql-tool \
    --plugin postgres \
    --ep 127.0.0.1 \
    -p 12345 \
    -u temporal \
    --pw temporal"

# Create both databases using vendor's tools
$TSQL create --db temporal
$TSQL --db temporal setup-schema -v 0.0
$TSQL --db temporal update-schema -d "${MAIN_SCHEMA_DIR}"

$TSQL create --db temporal_visibility
$TSQL --db temporal_visibility setup-schema -v 0.0
$TSQL --db temporal_visibility update-schema -d "${VISIBILITY_SCHEMA_DIR}"

# Start the server in the background
temporal-server &

# Create the default namespace whenever the server becomes ready
until tctl --ns default namespace describe < /dev/null; do
    echo "Default namespace not found. Creating..."
    sleep 0.2

    # FIXME retention period rather short
    tctl \
        --ns default \
        namespace register \
        --rd 1 \
        --desc "Default namespace for Temporal Server" \
        || echo "Creating default namespace failed."

done

# Even after creating the default namespace, it doesn't become immediately ready
# so wait for a bit
sleep 60

# Dump both databases pre-initialized with default namespace to be used for
# building the image
pg_dump --inserts temporal > mc_temporal.sql
pg_dump --inserts temporal_visibility > mc_temporal_visibility.sql
```
