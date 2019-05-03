#!/usr/bin/env perl

# start a single crawler_fetcher job
#
use strict;
use warnings;

use MediaWords::Crawler::Engine;

sub main
{
    my $crawler = MediaWords::Crawler::Engine->new();

    $crawler->run_fetcher();
}

main();
