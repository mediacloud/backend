#!/usr/bin/env perl

# execute a postgres query within a session that has the topic mapper's temporary dump tables

use strict;
use warnings;

use Data::Dumper;

use MediaWords::TM::Snapshot;
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

    MediaWords::TM::Snapshot::create_temporary_snapshot_views( $db, $timespan );

    print $db->query( $query )->text( 'neat' );
}

main();
