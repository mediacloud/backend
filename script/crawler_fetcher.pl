#!/usr/bin/env perl

# start a single crawler_fetcher job
#
use strict;
use warnings;

use MediaWords::Crawler::Engine;

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    my $crawler = MediaWords::Crawler::Engine->new( $db );

    $crawler->run_fetcher();
}

main();
