#!/usr/bin/env perl

# start a daemon that crawls all feeds in the database.
# see MediaWords::Crawler::Engine for details.

# usage: crawl.pl [ -t ] < num processes >
#
# -t option makes the crawler run with a pending_check_interval of 1 second,
# which is useful for testing environments to make a test crawler work quickly

use strict;
use warnings;

use MediaWords::Util::Config::Crawler;
use MediaWords::Crawler::Engine;

sub main
{
    my $use_test_interval = 0;
    if ( defined $ARGV[ 0 ] and $ARGV[ 0 ] eq '-t' )
    {
        $use_test_interval = 1;
        shift( @ARGV );
    }

    my $processes = MediaWords::Util::Config::Crawler::crawler_fetcher_forks();

    my $crawler = MediaWords::Crawler::Engine->new();

    $crawler->processes( $processes );
    $crawler->throttle( 1 );
    $crawler->sleep_interval( 10 );
    $crawler->pending_check_interval( 1 ) if ( $use_test_interval );

    $| = 1;

    $crawler->crawl();
}

main();
