#!/usr/bin/env perl
#
# Test Perl worker with a lock
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Job::Broker;
use MediaWords::Job::Lock;


sub run_job($)
{
    my $args = shift;

    my $test_id = $args->{ 'test_id' };
    my $x = $args->{ 'x' };
    my $y = $args->{ 'y' };

    INFO "Test ID $test_id: adding $x and $y...";

    # In a minute we should be able to add another job and make sure that it gets locked out from running
    sleep( 10 );

    return $x + $y;
}

sub main()
{
    my $app = MediaWords::Job::Broker->new( 'TestPerlWorkerLock' );

    my $lock = MediaWords::Job::Lock->new( 'TestPythonWorkerLock', 'test_id' );
    $app->start_worker( \&run_job, $lock );
}

main();
