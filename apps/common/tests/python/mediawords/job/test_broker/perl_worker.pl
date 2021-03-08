#!/usr/bin/env perl
#
# Test Perl worker
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Job::Broker;


sub run_job($)
{
    my $args = shift;

    my $x = $args->{ 'x' };
    my $y = $args->{ 'y' };

    INFO "Adding $x and $y...";

    return $x + $y;
}

sub main()
{
    my $app = MediaWords::Job::Broker->new( 'TestPerlWorker' );
    $app->start_worker( \&run_job );
}

main();
