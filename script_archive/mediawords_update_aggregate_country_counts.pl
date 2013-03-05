#!/usr/bin/perl

# update the aggregate vector tables needed to run clustering and dashboard systems
#
# requires a start date argument in '2009-10-01' format

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::StoryVectors;

sub main
{
    my $force = @ARGV && ( $ARGV[ 0 ] eq '-f' ) && shift( @ARGV );

    my ( $start_date, $end_date ) = @ARGV;

    if (   ( $start_date && !( $start_date =~ /^[0-9]{4,4}-[0-9]{2,2}-[0-9]{2,2}$/ ) )
        || ( $end_date && !( $end_date =~ /^[0-9]{4,4}-[0-9]{2,2}-[0-9]{2,2}$/ ) ) )
    {
        die( "date must be in the format YYYY-MM-DD" );
    }

    my $db = MediaWords::DB::connect_to_db;

    $db->dbh->{ AutoCommit } = 0;

    {
        MediaWords::StoryVectors::update_country_counts( $db, $start_date, $end_date, $force );
    }
}

main();
