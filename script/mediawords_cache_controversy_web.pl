#!/usr/bin/env perl

# run the queries to setup the controversy temporary tables for each controversy.
# this puts the controversy in the postgres buffer so that web queries to the controversy will
# not take a long time the first request to the controversy

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;

use MediaWords::Controller::Admin::CM;
use MediaWords::CM::Dump;
use MediaWords::CM::Mine;
use MediaWords::DB;

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    my $controversies = $db->query( "select * from controversies" )->hashes;

    for my $controversy ( @{ $controversies } )
    {
        print STDERR "$controversy->{ name }...\n";
        my $cds = $db->query( <<END, $controversy->{ controversies_id } )->hashes;
select * from controversy_dumps where controversies_id = ?
    order by controversy_dumps_id desc
END

        map { MediaWords::Controller::Admin::CM::add_periods_to_controversy_dump( $db, $_ ) } @{ $cds };

        my $latest_dump =
          MediaWords::Controller::Admin::CM::get_latest_full_dump_with_time_slices( $db, $cds, $controversy );

        next unless ( $latest_dump );

        my $cdts = $latest_dump->{ controversy_dump_time_slices }->[ 0 ];

        MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts, $controversy, 1 );
        MediaWords::CM::Dump::discard_temp_tables( $db );
    }
}

main();
