#!/usr/bin/env perl
#
# Test stateful Perl worker which runs forever
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Job::StatefulBroker;
use MediaWords::Job::State;
use MediaWords::Job::State::ExtraTable;


sub run_job($)
{
    my $args = shift;

    my $test_job_states_id = $args->{ 'test_job_states_id' };
    my $x = $args->{ 'x' };
    my $y = $args->{ 'y' };
    my $state_updater = $args->{ 'state_updater' };

    INFO "Running job in 'running' Perl worker (test job state ID: $test_job_states_id)...";

    # Sleep indefinitely to keep the job in "running" state
    while ( 1 ) {
        sleep( 10 );
    }
}

sub main()
{
    my $app = MediaWords::Job::StatefulBroker->new( 'TestPerlWorkerStateRunning' );

    my $lock = undef;
    my $extra_table = MediaWords::Job::State::ExtraTable->new( 'test_job_states', 'state', 'message' );
    my $state = MediaWords::Job::State->new( $extra_table );
    $app->start_worker( \&run_job, $lock, $state );
}

main();
