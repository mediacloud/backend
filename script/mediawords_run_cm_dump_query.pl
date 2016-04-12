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
    my ( $cdts_id, $query ) = @ARGV;

    binmode( STDOUT, ":utf8" );
    binmode( STDERR, ":utf8" );

    die( "usage: $0 <cdts_id> <query>" ) unless ( $query && $cdts_id );

    my $db = MediaWords::DB::connect_to_db;

    my $cdts = $db->find_by_id( "controversy_dump_time_slices", $cdts_id )
      || die( "Unknown controversy_dump_time_slice: '$cdts_id'" );

    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts );

    print $db->query( $query )->text( 'neat' );
}

main();
