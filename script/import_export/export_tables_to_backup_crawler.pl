#!/usr/bin/env perl
#
# Export "media", "feeds", ... table data needed to run a backup crawler
#
# Usage:
#
# 1) On production machine (database that is being exported), run:
#
#     # Export table data to "mediacloud-dump.sql"
#     ./script/run_with_carton.sh ./script/import_export/export_tables_to_backup_crawler.pl > mediacloud-dump.sql
#
# 2) On target machine (e.g. a backup crawler), run:
#
#     # Create database
#     createdb mediacloud
#
#     # Import empty schema
#     psql -f script/mediawords.sql mediacloud
#
#     # Import tables from "mediacloud-dump.sql"
#     psql -v ON_ERROR_STOP=1 -f mediacloud-dump.sql mediacloud
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use Text::CSV_XS;

sub _validate_table_foreign_keys($$)
{
    # If table's constraints aren't right, SQL would be pretty much invalid
    my ( $db, $table ) = @_;

    my $foreign_keys = $db->query(
        <<SQL,
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
          AND tc.table_name = ?
SQL
        $table
    )->hashes;

    foreach my $foreign_key ( @{ $foreign_keys } )
    {
        my $constraint_name      = $foreign_key->{ constraint_name };
        my $table_schema         = $foreign_key->{ table_schema };
        my $table_name           = $foreign_key->{ table_name };
        my $column_name          = $foreign_key->{ column_name };
        my $foreign_table_schema = $foreign_key->{ foreign_table_schema };
        my $foreign_table_name   = $foreign_key->{ foreign_table_name };
        my $foreign_column_name  = $foreign_key->{ foreign_column_name };

        INFO "Validating foreign key '$constraint_name' for table '$table'...";

        my $sql = "
            SELECT DISTINCT a.$column_name
            FROM $table_schema.$table_name AS a
                LEFT JOIN $foreign_table_schema.$foreign_table_name AS b
                    ON a.$column_name = b.$foreign_column_name
            WHERE a.$column_name IS NOT NULL
              AND b.$foreign_column_name IS NULL
            ORDER BY a.$column_name
        ";

        my $unreferenced_rows = $db->query( $sql )->flat;
        if ( scalar @{ $unreferenced_rows } )
        {
            die "Table '$table' has unreferenced rows for constraint '$constraint_name': " .
              join( ', ', @{ $unreferenced_rows } ) . "; SQL: $sql";
        }

        INFO "Done validating foreign key '$constraint_name' for table '$table'.";
    }
}

sub _print_table_csv_to_stdout($$)
{
    my ( $db, $table ) = @_;

    my $column_names       = $db->query( "SELECT * FROM $table LIMIT 0" )->columns;
    my $primary_key_column = $db->primary_key_column( $table );

    print <<"SQL";
--
-- Table '$table'
--
SQL

    print "COPY $table (" . join( ', ', @{ $column_names } ) . ") FROM STDIN WITH CSV;\n";

    my $csv = Text::CSV_XS->new(
        {    #
            binary         => 1,    #
            quote_empty    => 1,    #
            quote_space    => 1,    #
            blank_is_undef => 1,    #
            empty_is_undef => 0,    #
        }
    ) or die "" . Text::CSV_XS->error_diag();

    my $res = $db->query( "SELECT * FROM $table ORDER BY $primary_key_column" );
    while ( my $row = $res->array() )
    {
        $csv->combine( @{ $row } );
        print $csv->string . "\n";
    }

    print '\.' . "\n";

    print <<"SQL";

-- Update sequence head
SELECT setval(
    pg_get_serial_sequence('$table', '$primary_key_column'),
    (SELECT max($primary_key_column)+1 FROM $table)
);
SQL

    print "\n";

}

sub main
{
    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    # Autoflush
    $| = 1;

    my $db = MediaWords::DB::connect_to_db;

    # Tables to export
    my $tables = [ 'tag_sets', 'media', 'feeds', 'tags', 'media_tags_map', 'feeds_tags_map', ];

    $db->begin;

    INFO "Validating foreign keys...";
    my @foreign_key_errors;
    foreach my $table ( @{ $tables } )
    {
        INFO "Validating foreign keys for table '$table'...";

        # Aggregate errors into array to be able to print a one huge complaint
        eval { _validate_table_foreign_keys( $db, $table ); };
        if ( $@ )
        {
            my $error = $@;
            WARN "Validating foreign key for table '$table' failed: $error";
            push( @foreign_key_errors, $error );
        }
    }
    if ( scalar @foreign_key_errors > 0 )
    {
        die "One or more foreign key checks failed, won't continue as resulting SQL would be invalid: " .
          join( "\n", @foreign_key_errors );
    }

    INFO "Done validating foreign keys.";

    print <<SQL;
--
-- This is a dataset needed for running a backup crawler.
--
-- Import this dump into the backup crawler's PostgreSQL instance.
--

BEGIN;

--
-- Die if schema has not been initialized
--
DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = CURRENT_SCHEMA()
          AND table_name = 'media'
    ) THEN
        RAISE EXCEPTION 'Table "media" does not exist, please initialize schema.';
    END IF;
END\$\$;

--
-- Die if something's already in the database
--
DO \$\$
BEGIN
    IF EXISTS (SELECT 1 FROM media) THEN
        RAISE EXCEPTION 'Table "media" already contains data, please purge the database.';
    END IF;
END\$\$;

--
-- Temporarily disable constraints to speed up import
--
SET CONSTRAINTS ALL DEFERRED;

--
-- Truncate "tag_sets" table (might already have something)
--
TRUNCATE tag_sets CASCADE;

SQL

    INFO "Exporting tables...";
    foreach my $table ( @{ $tables } )
    {
        INFO "Exporting table '$table'...";
        _print_table_csv_to_stdout( $db, $table );
    }
    INFO "Done exporting tables.";

    $db->commit;

    print <<SQL;

--
-- Reenable constraints
--
SET CONSTRAINTS ALL IMMEDIATE;

COMMIT;

SQL
}

main();
