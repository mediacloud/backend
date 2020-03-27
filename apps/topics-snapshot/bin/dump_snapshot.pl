#!/usr/bin/env perl

use MediaWords::DB;
use MediaWords::TM::Dump;

sub main
{
	my ( $snapshots_id ) = @ARGV;


	die( "usage: $0 <snapshots_id>" ) unless ( $snapshots_id );

	my $db = MediaWords::DB::connect_to_db();

	$db->require_by_id( 'snapshots', $snapshots_id );

	my $timespans = $db->query( <<SQL, $snapshots_id )->hashes();
select * from timespans where snapshots_id = ? order by timespans_id
SQL

	for my $t ( @{ $timespans } )
	{
			MediaWords::TM::Dump::dump_timespan( $db, $t );
	} 
} 

main();
