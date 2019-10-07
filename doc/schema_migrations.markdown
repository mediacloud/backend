# Schema and migrations

App `postgresql-server` provides the rest of the apps with the capability of storing and reading data from PostgreSQL. App comes pre-loaded with full schema (located in `schema/mediawords.sql`) at build time.

Additionally, on every start the wrapper script will test the instance for the schema version (stored in `database_variables` table) that's currently being used in the attached data volume, and if the schema version is older than the current schema version in `schema/mediawords.sql`, it will execute appropriate migration scripts (located in `schema/migrations/`) to get the data volume's schema to the newest version.

The schema migrations get applied privately, i.e. before the database instance actually goes "live" and becomes accessible to other apps, so every app is guaranteed to be connecting to the database instance with the most up-to-date schema version.

## Updating schema

To make changes to the schema:

1. Edit the main schema file (located in `schema/mediawords.sql` file under the `postgresql-server` app) to make required changes;
2. In the main schema, update the `MEDIACLOUD_DATABASE_SCHEMA_VERSION` variable at the top of the file by increasing the schema version;
3. In the schema migrations directory (located in `schema/migrations/` directory under the `postgresql-server` app), add a new migration file with the name `mediawords-<old-schema-version>-<new-schema-version>.sql`; in the migration file, add SQL statements that both
   1. makes the required changes in the schema itself (creates / drops tables, columns, etc.), and
   2. sets the `MEDIACLOUD_DATABASE_SCHEMA_VERSION` variable to the newest schema version;
4. Rebuild `postgresql-server` app image with `build.py` developer script, or just `git push` the changes to for the CI server to rebuild everything;
5. Pull the updated `postgresql-server` image in production, remove old container running an outdated image, and create a new container using the updated image and a data volume from the old container.
6. Start the container. The wrapper script in the container will temporarily start a private instance of PostgreSQL and apply the schema migrations before starting a public instance of the service for other apps to use.
