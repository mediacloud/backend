#!/usr/bin/env perl
#
# Test stateful Perl worker which reports a custom state
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

    unless ( $state_updater ) {
        LOGDIE "State updater is not set.";
    }

    INFO "Running job in 'custom' Perl worker (test job state ID: $test_job_states_id)...";

    my $db = MediaWords::DB::connect_to_db();

    $state_updater->update_job_state( $db, 'foo', 'bar' );

    # Sleep indefinitely to keep the job in "custom" state
    while ( 1 ) {
        sleep( 10 );
    }
}

sub main()
{
    my $app = MediaWords::Job::StatefulBroker->new( 'TestPerlWorkerStateCustom' );

    my $lock = undef;
    my $extra_table = MediaWords::Job::State::ExtraTable->new( 'test_job_states', 'state', 'message' );
    my $state = MediaWords::Job::State->new( $extra_table );
    $app->start_worker( \&run_job, $lock, $state );
}

main();
