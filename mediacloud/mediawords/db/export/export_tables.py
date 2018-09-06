import csv
import sys

from mediawords.db.handler import DatabaseHandler
from mediawords.util.log import create_logger

log = create_logger(__name__)


class McValidateTableForeignKeysException(Exception):
    """__validate_table_foreign_keys() exception."""
    pass


# noinspection SqlResolve
def __validate_table_foreign_keys(db: DatabaseHandler, table: str) -> None:
    """Validate all table's foreign keys; raise McValidateTableForeignKeysException if any of the keys are invalid.

    If table's constraints aren't right, SQL would be pretty much invalid."""

    foreign_keys = db.query("""
        SELECT
            tc.constraint_name,
            tc.table_schema,
            tc.table_name,
            kcu.column_name,
            ccu.table_schema AS foreign_table_schema,
            ccu.table_name AS foreign_table_name,
            ccu.column_name AS foreign_column_name

        FROM information_schema.table_constraints AS tc
            JOIN information_schema.key_column_usage AS kcu
                ON tc.constraint_name = kcu.constraint_name
            JOIN information_schema.constraint_column_usage AS ccu
                ON ccu.constraint_name = tc.constraint_name
        WHERE constraint_type = 'FOREIGN KEY'
          AND tc.table_schema = 'public'
          AND tc.table_name = %(table)s
    """, {'table': table}).hashes()

    foreign_key_errors = []

    for foreign_key in foreign_keys:
        constraint_name = foreign_key['constraint_name']

        log.info("Validating foreign key '%s' for table '%s'..." % (constraint_name, table))

        sql = """
            SELECT DISTINCT a.%(column_name)s
            FROM %(table_schema)s.%(table_name)s AS a
                LEFT JOIN %(foreign_table_schema)s.%(foreign_table_name)s AS b
                    ON a.%(column_name)s = b.%(foreign_column_name)s
            WHERE a.%(column_name)s IS NOT NULL
              AND b.%(foreign_column_name)s IS NULL
            ORDER BY a.%(column_name)s
        """ % {
            'column_name': foreign_key['column_name'],
            'table_schema': foreign_key['table_schema'],
            'table_name': table,
            'foreign_table_schema': foreign_key['foreign_table_schema'],
            'foreign_table_name': foreign_key['foreign_table_name'],
            'foreign_column_name': foreign_key['foreign_column_name'],
        }

        unreferenced_rows = db.query(sql).flat()

        if len(unreferenced_rows) > 0:
            error = """
                Table '%(table)s' has unreferenced rows for constraint '%(constraint_name)s':
                %(unreferenced_rows)s; SQL: %(sql)s
            """ % {
                'table': table,
                'constraint_name': constraint_name,
                'unreferenced_rows': ', '.join(unreferenced_rows),
                'sql': sql,
            }
            foreign_key_errors.append(error)
            log.warning(error)
        else:
            log.info("Foreign key '%s' for table '%s' looks fine." % (constraint_name, table))

    if len(foreign_key_errors) > 0:
        raise McValidateTableForeignKeysException(
            "One or more foreign key checks failed for table '%(table)s': %(foreign_key_errors)s" % {
                'table': table,
                'foreign_key_errors': "\n".join(foreign_key_errors)
            }
        )


def __print_table_csv_to_stdout(db: DatabaseHandler, table: str) -> None:
    """Print table dump to STDOUT."""

    column_names = db.query("SELECT * FROM %s LIMIT 0" % table).columns()
    primary_key_column = db.primary_key_column(object_name=table)

    print("""
--
-- Table '%(table)s'
--

    """ % {'table': table})

    # Python's "csv" module doesn't bother to differentiate between empty strings and "None" values:
    #
    # http://stackoverflow.com/a/11379550/200603
    #
    # ...so we're exporting the table in "TEXT" format with a cumbersome "\\N" (two-backslashes-N) mark for NULL values.
    print("COPY %(table)s (%(column_names)s) FROM STDIN WITH (FORMAT TEXT, NULL '\\\\N');" % {
        'table': table,
        'column_names': ', '.join(column_names),
    })

    csv_writer = csv.writer(sys.stdout, delimiter="\t", escapechar="\\", quoting=csv.QUOTE_NONE)

    res = db.query("SELECT * FROM %(table)s ORDER BY %(primary_key_column)s" % {
        'table': table,
        'primary_key_column': primary_key_column,
    })

    postgresql_null_value = '\\N'
    postgresql_end_of_data = '\.'
    while True:
        row = res.array()
        if row is None:
            break
        else:
            csv_writer.writerow([postgresql_null_value if val is None else val for val in row])

    print(postgresql_end_of_data)

    print("""

-- Update sequence head
SELECT setval(
    pg_get_serial_sequence('%(table)s', '%(primary_key_column)s'),
    (SELECT max(%(primary_key_column)s)+1 FROM %(table)s)
);

    """ % {
        'table': table,
        'primary_key_column': primary_key_column,
    })


class McPrintExportedTablesToBackupCrawlerException(Exception):
    """print_exported_tables_to_backup_crawler() exception."""
    pass


# noinspection SqlResolve
def print_exported_tables_to_backup_crawler(db: DatabaseHandler) -> None:
    """Export tables by printing their SQL dump to STDOUT."""

    # Tables to export
    tables = ['tag_sets', 'media', 'feeds', 'tags', 'media_tags_map', 'feeds_tags_map']

    db.begin()

    log.info("Validating foreign keys...")
    foreign_key_errors = []

    for table in tables:
        log.info("Validating foreign keys for table '%s'..." % table)

        # Aggregate errors into array to be able to print a one huge complaint
        try:
            __validate_table_foreign_keys(db=db, table=table)
        except McValidateTableForeignKeysException as ex:
            error = str(ex)
            log.warning("Validating foreign key for table '%s' failed: %s" % (table, error))
            foreign_key_errors.append(error)

    if len(foreign_key_errors):
        raise McPrintExportedTablesToBackupCrawlerException(
            "One or more foreign key checks failed, won't continue as resulting SQL would be invalid:\n\n%s" %
            str(foreign_key_errors)
        )

    log.info("Done validating foreign keys.")

    print("""
--
-- This is a dataset needed for running a backup crawler.
--
-- Import this dump into the backup crawler's PostgreSQL instance.
--

BEGIN;

--
-- Die if schema has not been initialized
--
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = CURRENT_SCHEMA()
          AND table_name = 'media'
    ) THEN
        RAISE EXCEPTION 'Table "media" does not exist, please initialize schema.';
    END IF;
END$$;

--
-- Die if something's already in the database
--
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM media) THEN
        RAISE EXCEPTION 'Table "media" already contains data, please purge the database.';
    END IF;
END$$;

--
-- Temporarily disable constraints to speed up import
--
SET CONSTRAINTS ALL DEFERRED;

--
-- Truncate "tag_sets" table (might already have something)
--
TRUNCATE tag_sets CASCADE;

    """)

    log.info("Exporting tables...")
    for table in tables:
        log.info("Exporting table '%s'..." % table)
        __print_table_csv_to_stdout(db=db, table=table)
    log.info("Done exporting tables.")

    db.commit()

    print("""
--
-- Reenable constraints
--
SET CONSTRAINTS ALL IMMEDIATE;

COMMIT;
    """)
