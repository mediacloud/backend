#!/usr/bin/env perl

# execute a postgres query within a session that has the cm temporary dump tables

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;

use MediaWords::CM::Dump;
use MediaWords::DB;

sub main
{
    my ( $timespans_id, $query ) = @ARGV;

    binmode( STDOUT, ":utf8" );
    binmode( STDERR, ":utf8" );

    die( "usage: $0 <timespans_id> <query>" ) unless ( $query && $timespans_id );

    my $db = MediaWords::DB::connect_to_db;

    my $timespan = $db->find_by_id( "timespans", $timespans_id )
      || die( "Unknown timespan: '$timespans_id'" );

    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $timespan );

    print $db->query( $query )->text( 'neat' );
}

main();
