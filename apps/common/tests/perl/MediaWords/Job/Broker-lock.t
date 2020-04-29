package BrokerTest::Test;

use strict;
use warnings;

use lib '/opt/mediacloud/tests/perl/MediaWords/Job/';
use base qw(SetupBrokerTest);

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Data::Dumper;
use Test::More;

use MediaWords::Job::Broker;

local $| = 1;


sub worker_paths()
{
    my $workers_path = '/opt/mediacloud/tests/perl/MediaWords/Job/Broker-lock';

    # Need 2+ workers to see the effect of locking
    my $worker_count = 2;

    return [
        {
            'queue_name' => 'TestPerlWorkerLock',
            'worker_path' => "$workers_path/perl_worker.pl",
            'worker_count' => $worker_count,
        },
        {
            'queue_name' => 'TestPythonWorkerLock',
            'worker_path' => "$workers_path/python_worker.py",
            'worker_count' => $worker_count,
        }
    ];
}

sub broker_class()
{
    return 'MediaWords::Job::Broker';
}

sub test_lock : Test(no_plan)
{
    my $self = shift;

    my $lock_test_id = 123;

    for my $worker (@{ $self->{ WORKERS }}) {

        INFO "Adding the first job to the queue which will take 10+ seconds to run...";
        my $job_id = $worker->{ 'app' }->add_to_queue( { 'test_id' => $lock_test_id, 'x' => 2, 'y' => 3 } );

        INFO "Waiting for the job to reach the queue...";
        sleep( 2 );

        # While assuming that the first job is currently running (and thus is "locked"):
        INFO "Testing if a subsequent job fails with a lock problem...";
        is(
            $worker->{ 'app' }->run_remotely( { 'test_id' => $lock_test_id, 'x' => 3, 'y' => 4 } ),
            undef,
            "Second job shouldn't work",
        );

        INFO "Waiting for the first job to finish...";
        is( $worker->{ 'app' }->get_result( $job_id ), 5 );
    }
}

sub main()
{
    Test::Class->runtests;
}

main();
