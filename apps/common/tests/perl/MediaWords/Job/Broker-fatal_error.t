package BrokerTest::Test;

use strict;
use warnings;

use lib '/opt/mediacloud/tests/perl/MediaWords/Job/';
use base qw(SetupBrokerTest);

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Data::Dumper;
use Errno;
use Proc::ProcessTable;
use Test::More;

use MediaWords::Job::Broker;

local $| = 1;


sub worker_paths()
{
    my $workers_path = '/opt/mediacloud/tests/perl/MediaWords/Job/Broker-fatal_error';

    return [
        {
            'queue_name' => 'TestPerlWorkerFatalError',
            'worker_path' => "$workers_path/perl_worker.pl",
        },
        {
            'queue_name' => 'TestPythonWorkerFatalError',
            'worker_path' => "$workers_path/python_worker.py",            
        }
    ];
}

sub broker_class()
{
    return 'MediaWords::Job::Broker';
}

sub _pid_exists($)
{
    my $pid = shift;

    say STDERR "Looking for PID $pid";

    my $t = Proc::ProcessTable->new();

    foreach my $process ( @{ $t->table } ) {
        if ( $process->pid == $pid ) {

            say STDERR "Testing PID " . $process->pid . " with state " . $process->state;

            # Zombie processes don't count
            if ( $process->state ne 'defunct' ) {
                return 1;
            }
        }
    }

    return 0;
}

sub test_fatal_error : Test(no_plan)
{
    my $self = shift;

    INFO "Waiting for workers to start...";
    sleep( 5 );
    INFO "Done waiting";

    for my $worker (@{ $self->{ WORKERS }}) {

        my $worker_pid = $worker->{ 'process_pids' }->[ 0 ];
        ok( _pid_exists( $worker_pid ), "PID $worker_pid is still running" );

        $worker->{ 'app' }->add_to_queue();

        for ( my $retry = 0; $retry < 20; ++$retry ) {
            INFO "Waiting for the process $worker_pid to stop (retry $retry)...";
            if ( _pid_exists( $worker_pid ) ) {
                sleep( 1 );
            } else {
                INFO "Process stopped";
                last;
            }
        }

        ok( ! _pid_exists( $worker_pid ), "Process has managed to stop" );

        # Not sure how to test exit code here
    }
}

sub main()
{
    Test::Class->runtests;
}

main();
