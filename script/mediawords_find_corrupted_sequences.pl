#!/usr/bin/env perl

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use utf8;
use MediaWords::DB;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

sub main
{

    my $db = MediaWords::DB::connect_to_db;

    my $table_query = <<'SQL';
SELECT *, Pg_get_serial_sequence(tablename, id_column)
FROM   (SELECT t.oid     AS tableid,
               t.relname AS tablename,
               t.relname
                || '_id' AS id_column,
               c.oid     AS constraintid,
               conname   AS constraintname
        FROM   pg_constraint c
               JOIN pg_class t
                 ON ( c.conrelid = t.oid )
        WHERE  conname LIKE '%_pkey'
               AND NOT (t.relname in 
                    ( 'url_discover_counts' ) )
        ORDER  BY t.relname) AS tables_with_pkeys
WHERE  NOT ( tablename IN ( 'url_discovery_counts'
                                       ) );  
SQL

    my $tables = $db->query( $table_query )->hashes;

    foreach my $table ( @$tables )
    {

        #say Dumper( $table );

        if ( !$table->{ pg_get_serial_sequence } )
        {
            say 'skipping table ' . $table->{ tablename } . ' that does not have a sequence id ';
            next;
        }

        #say 'table '  . $table->{ tablename };

        # TEMPORARY HACK
        next if "story_similarities_100_short" eq $table->{ tablename };

        my $sequence_query =
          'select * from (select max(' .
          $table->{ id_column } . ' ) as max_id, nextval( ' . "'" . $table->{ pg_get_serial_sequence } .
          "'" . ' ) as sequence_val from  ' . $table->{ tablename } . ' ) as id_and_sequence where max_id >= sequence_val ';

        #say STDERR $sequence_query;

        my $table_info = $db->query( $sequence_query )->hash;

        if ( $table_info )
        {
            say "Invalid sequence value for table $table->{ tablename } ";
            say Dumper( $table_info );
            exit;
        }
    }

}

main();
