#!/usr/bin/env perl
#
# Test stateful Perl worker which completes successfully
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Job::StatefulBroker;
use MediaWords::Job::State;


sub run_job($)
{
    my $args = shift;

    my $test_job_states_id = $args->{ 'test_job_states_id' };
    my $x = $args->{ 'x' };
    my $y = $args->{ 'y' };
    my $state_updater = $args->{ 'state_updater' };

    INFO "Starting 'completed' Perl worker (test job state ID: $test_job_states_id)...";

    return $x + $y;
}

sub main()
{
    my $app = MediaWords::Job::StatefulBroker->new( 'TestPerlWorkerStateCompleted' );

    my $lock = undef;
    my $state = MediaWords::Job::State->new( 'test_job_states', 'state', 'message' );
    $app->start_worker( \&run_job, $lock, $state );
}

main();
