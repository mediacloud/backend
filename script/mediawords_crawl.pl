#!/usr/bin/env perl

# start a daemon that crawls all feeds in the database.
# see MediaWords::Crawler::Engine.pm for details.

# usage: mediawords_crawl.pl [ -t ] < num processes >
#
# -t option makes the crawler run with a pending_check_interval of 1 second,
# which is useful for testing environments to make a test crawler work quickly

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::Crawler::Engine;

sub main
{
    my $use_test_interval = 0;
    if ( $ARGV[ 0 ] eq '-t' )
    {
        $use_test_interval = 1;
        shift( @ARGV );
    }

    my ( $processes ) = @ARGV;

    $processes ||= 1;

    my $crawler = MediaWords::Crawler::Engine->new();

    $crawler->processes( $processes );
    $crawler->throttle( 1 );
    $crawler->sleep_interval( 10 );
    $crawler->pending_check_interval( 1 ) if ( $use_test_interval );

    $| = 1;

    $crawler->crawl();
}

main();
