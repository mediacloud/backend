package SetupBrokerTest;

use strict;
use warnings;
use base qw(Test::Class);

use Test::More;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Job::Broker;
use MediaWords::Job::StatefulBroker;

local $| = 1;


# Abstract method
sub worker_paths()
{
    LOGDIE "Abstract method.";
}

# Abstract method
sub broker_class()
{
    LOGDIE "Abstract method.";
}

sub start_workers : Test(startup)
{
    my $self = shift;

    DEBUG "Starting workers: " . Dumper( $self->worker_paths() );

    $self->{ WORKERS } = [];

    for my $worker ( @{ $self->worker_paths() } ) {
        ok( -f $worker->{ 'worker_path' }, "Worker script exists at " . $worker->{ 'worker_path' } );
        ok( -x $worker->{ 'worker_path' }, "Worker script is executable at " . $worker->{ 'worker_path' } );

        my $broker_class = $self->broker_class();

        my $worker_app = $broker_class->new( $worker->{ 'queue_name' } );
        DEBUG "Worker app: " . Dumper( $worker_app );

        my $process_pids = [];

        unless ( defined $worker->{ 'worker_count' } ) {
            $worker->{ 'worker_count' } = 1;
        }

        ok( $worker->{ 'worker_count' }, "Worker count has to be positive" );

        for ( my $x = 0; $x < $worker->{ 'worker_count' }; ++$x ) {

            my $worker_pid = fork();
            unless ( $worker_pid ) {
                setpgrp();
                system( $worker->{ 'worker_path' } );
                exit( 0 );
            } else {
                push( @{ $process_pids }, $worker_pid );
            }
        }

        push( @{ $self->{ WORKERS } }, {
            'app' => $worker_app,
            'process_pids' => $process_pids,
        } );
    }

    INFO "Waiting for workers to start...";
    sleep( 5 );
    INFO "Done waiting";
}

sub stop_workers : Test(shutdown)
{
    my $self = shift;

    INFO "Killing workers";

    for my $worker (@{ $self->{ WORKERS }}) {
        for my $pid (@{ $worker->{ process_pids }}) {
            INFO "Killing worker with PID $pid";
            kill -9, getpgrp( $pid );
        }
    }
}

1;
