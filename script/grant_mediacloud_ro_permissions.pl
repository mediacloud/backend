#!/usr/bin/env perl

# grant the mediacloud_ro user read privileges to all tables

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    $db->query( <<'SQL' );
DO $do$
DECLARE
    sch text;
BEGIN
    FOR sch IN SELECT nspname FROM pg_namespace
    LOOP
        EXECUTE format($$ GRANT select on all tables in SCHEMA %I TO mediacloud_ro $$, sch);
        EXECUTE format($$ GRANT all privileges on SCHEMA %I TO mediacloud_ro $$, sch);
    END LOOP;
END;
$do$;
SQL

}

main();
