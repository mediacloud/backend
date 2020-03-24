package BrokerTest::Test;

use strict;
use warnings;

use lib '/opt/mediacloud/tests/perl/MediaWords/Job/';
use base qw(SetupBrokerTest);

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Data::Dumper;
use Sys::Hostname;
use Test::More;

use MediaWords::DB;
use MediaWords::Job::StatefulBroker;
use MediaWords::Job::State;
use MediaWords::Util::ParseJSON;


local $| = 1;


sub worker_paths()
{
    my $workers_path = '/opt/mediacloud/tests/perl/MediaWords/Job/Broker-state';

    return [

        {
            'queue_name' => 'TestPerlWorkerStateCompleted',
            'worker_path' => "$workers_path/perl_worker_completed.pl",
        },
        {
            'queue_name' => 'TestPerlWorkerStateCustom',
            'worker_path' => "$workers_path/perl_worker_custom.pl",
        },
        {
            'queue_name' => 'TestPerlWorkerStateError',
            'worker_path' => "$workers_path/perl_worker_error.pl",
        },
        {
            'queue_name' => 'TestPerlWorkerStateRunning',
            'worker_path' => "$workers_path/perl_worker_running.pl",
        },

        {
            'queue_name' => 'TestPythonWorkerStateCompleted',
            'worker_path' => "$workers_path/python_worker_completed.py",
        },
        {
            'queue_name' => 'TestPythonWorkerStateCustom',
            'worker_path' => "$workers_path/python_worker_custom.py",
        },
        {
            'queue_name' => 'TestPythonWorkerStateError',
            'worker_path' => "$workers_path/python_worker_error.py",
        },
        {
            'queue_name' => 'TestPythonWorkerStateRunning',
            'worker_path' => "$workers_path/python_worker_running.py",
        },

    ];
}

sub broker_class()
{
    return 'MediaWords::Job::StatefulBroker';
}

sub test_state : Test(no_plan)
{
    my $self = shift;

    my $db = MediaWords::DB::connect_to_db();

    $db->query(<<SQL
        CREATE TABLE IF NOT EXISTS test_job_states (
            test_job_states_id  SERIAL  PRIMARY KEY,
            state               TEXT    NOT NULL,
            message             TEXT    NOT NULL
        );
SQL
    );

    # Clean up leftovers from previous runs
    $db->query("DELETE FROM job_states");
    $db->query("DELETE FROM test_job_states");

    my $common_kwargs = { 'x' => 2, 'y' => 3 };
    my $expected_result = $common_kwargs->{ 'x' } + $common_kwargs->{ 'y' };

    my $worker_types = [
        {
            'queue_name_ends_with' => 'Completed',
            'expected_result' => $expected_result,
            'expected_state' => $MediaWords::Job::State::STATE_COMPLETED,
            'expected_message' => '',
        },
        {
            'queue_name_ends_with' => 'Custom',
            'expected_result' => undef, # never finishes
            'expected_state' => 'foo',
            'expected_message' => 'bar',
        },
        {
            'queue_name_ends_with' => 'Error',
            'expected_result' => undef, # fails
            'expected_state' => $MediaWords::Job::State::STATE_ERROR,
            'expected_message' => "Well, it didn't work",
        },
        {
            'queue_name_ends_with' => 'Running',
            'expected_result' => undef, # never finishes
            'expected_state' => $MediaWords::Job::State::STATE_RUNNING,
            'expected_message' => '',
        },
    ];

    for my $worker_type ( @{ $worker_types } ) {

        my $applicable_workers = [];
        for my $worker (@{ $self->{ WORKERS }}) {
            my $queue_name_ends_with = $worker_type->{ 'queue_name_ends_with' };
            if ( $worker->{ 'app' }->queue_name() =~ m/\Q$queue_name_ends_with\E$/ ) {
                push( @{ $applicable_workers }, $worker );
            }
        }

        ok( scalar( @{ $applicable_workers }), "No workers found for type " . Dumper( $worker_type ));

        for my $worker (@{ $applicable_workers }) {

            $db->query( "DELETE FROM test_job_states" );

            my $test_job_state = $db->insert( 'test_job_states', {
                'state' => '',
                'message' => '',
            });
            my $test_job_states_id = $test_job_state->{ 'test_job_states_id' };

            my $worker_args = { 'test_job_states_id' => $test_job_states_id };
            my $kwargs = { %{ $common_kwargs }, %{ $worker_args } };

            my $job_id = $worker->{ 'app' }->add_to_queue( $kwargs );

            if ( $worker_type->{ 'expected_result' } ) {
                INFO "Fetching and comparing result for worker " . Dumper( $worker_type );
                my $result = $worker->{ 'app' }->get_result( $job_id );
                is( $result, $expected_result, "Result for worker " . Dumper( $worker_type ));
            } else {
                # Just wait a bit for the thing to finish
                INFO "No result is expected, waiting for worker " . Dumper( $worker_type );
                sleep( 5 );
            }

            my $job_states = $db->query(<<SQL,
                SELECT *
                FROM job_states
                WHERE class = ?
SQL
                $worker->{ 'app' }->queue_name(),
            )->hashes();
            is( scalar(@{ $job_states }), 1, "Job state count for worker " . Dumper( $worker_type ) );

            my $job_state = $job_states->[ 0 ];

            is( $job_state->{ 'state' }, $worker_type->{ 'expected_state' }, "Job state for worker " . Dumper( $worker_type ) . ", row: " . Dumper( $job_state ) );
            my $expected_message = $worker_type->{ 'expected_message' };
            like( $job_state->{ 'message' }, qr/\Q$expected_message\E/, "Job message for worker " . Dumper( $worker_type ) );
            ok( $job_state->{ 'last_updated' }, "Job's last updated for worker " . Dumper( $worker_type ) );
            is_deeply( MediaWords::Util::ParseJSON::decode_json( $job_state->{ 'args' }), $kwargs, "Job's arguments for worker " . Dumper( $worker_type ) );
            is( $job_state->{ 'hostname' }, Sys::Hostname::hostname, "Job's hostname for worker " . Dumper( $worker_type ) );

            my $custom_table_states = $db->select( 'test_job_states', '*' )->hashes();
            is( scalar( @{ $custom_table_states }), 1, "Custom table states count for worker " . Dumper( $worker_type ) );
            my $custom_table_state = $custom_table_states->[ 0 ];

            is( $custom_table_state->{ 'state' }, $worker_type->{ 'expected_state' }, "Custom table state for worker " . Dumper( $worker_type ) . ", row: " . Dumper( $job_state ) );
            like( $custom_table_state->{ 'message' }, qr/\Q$expected_message\E/, "Custom table message for worker " . Dumper( $worker_type ) );
        }

    }
}

sub main()
{
    Test::Class->runtests;
}

main();
