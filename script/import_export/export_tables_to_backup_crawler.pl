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

    my $csv = Text::CSV_XS->new( { binary => 1 } );
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

    # Export tables
    my $tables = [ 'tag_sets', 'media', 'feeds', 'tags', 'media_tags_map', 'feeds_tags_map', ];
    foreach my $table ( @{ $tables } )
    {
        INFO "Exporting table '$table'...";
        _print_table_csv_to_stdout( $db, $table );
    }

    print <<SQL;

--
-- Reenable constraints
--
SET CONSTRAINTS ALL IMMEDIATE;

COMMIT;

SQL
}

main();
