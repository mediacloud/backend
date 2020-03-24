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
    my $workers_path = '/opt/mediacloud/tests/perl/MediaWords/Job/Broker';

    return [
        {
            'queue_name' => 'TestPerlWorker',
            'worker_path' => "$workers_path/perl_worker.pl",
        },
        {
            'queue_name' => 'TestPythonWorker',
            'worker_path' => "$workers_path/python_worker.py",            
        }
    ];
}

sub broker_class()
{
    return 'MediaWords::Job::Broker';
}

sub test_run_remotely : Test(no_plan)
{
    my $self = shift;

    for my $worker (@{ $self->{ WORKERS }}) {
        my $result = $worker->{ 'app' }->run_remotely( { 'x' => 1, 'y' => 2 });
        is( $result, 3, "Result is correct for worker " . Dumper( $worker ) );
    }

}

sub test_add_to_queue_get_result : Test(no_plan)
{
    my $self = shift;

    for my $worker (@{ $self->{ WORKERS }}) {
        my $job_id = $worker->{ 'app' }->add_to_queue( { 'x' => 3, 'y' => 4 });
        INFO "Job ID: $job_id for worker " . Dumper( $worker );

        my $result = $worker->{ 'app' }->get_result( $job_id );
        is( $result, 7, "Result is correct for worker " . Dumper( $worker ) );
    }
}

sub main()
{
    Test::Class->runtests;
}

main();
