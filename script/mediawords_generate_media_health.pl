#!/usr/bin/env perl

# generate media_health table, which contains denormalized results of analytical queries run on
# the media_stats table to enable quick analysis of the health of individual media sources.
#
# also generate a report that includes a summary of overall system health as well as alerts
# for specific media that appear unhealthy

use strict;
use warnings;

use MediaWords::DB;
use MediaWords::DBI::Media::Health;

sub main
{
    binmode( STDOUT, ':utf8' );

    my $db = MediaWords::DB::connect_to_db;

    MediaWords::DBI::Media::Health::generate_media_health( $db );

    MediaWords::DBI::Media::Health::print_health_report( $db );
}

main();
