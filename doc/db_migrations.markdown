(DEVELOPER) CHANGING THE DATABASE SCHEMA
========================================

We use a versioning system to make sure that any changes to the database schema are accompanies by commands that
will update existing databases.

To make a change to the database schema:

1. make your desired schema changes in schema/mediawords.sql;

2. increment the version number in the following line in the same file;

```
MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4639;
```

3. run script/generate_empty_sql_migration.sh;

4. add the necessary 'alter' commands to the bottom of the generated file to update existing databases to the new schema.


EXAMPLE
-------

This example uses +- line prefixes to indicate lines added/removed from a file.

1. edit mediawords.sql to add the 'awesome_score' field to the media table:

```
create table media (
    media_id            serial          primary key,
    url                 varchar(1024)   not null,
    name                varchar(128)    not null,
+   awesome_score       bigint          not null,
```

2. edit mediawords.sql to increment the version:

```
-MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4639;
+MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4640;
```


3. run script/generate_empty_sql_migration.sh

```
hroberts@namshub:mediacloud [master]$ script/generate_empty_sql_migration.sh
generated schema/migrations/mediawords-4639-4640.sql and added it to git commit
```

4. edit schema/migrations/mediawords-4639-4640.sql to add the alter table command:

```
SELECT set_database_schema_version();
+alter table media add awesome_score bigint not null;
```
