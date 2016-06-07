use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::Util::Config;

{

    package MediaWords::AbstractJob::Configuration;

    #
    # Implements MediaCloud::JobManager::Configuration with values from Media Cloud's configuration
    #

    use Moose;
    use MediaCloud::JobManager::Configuration;
    use MediaCloud::JobManager::Broker::Gearman;
    use MediaCloud::JobManager::Broker::RabbitMQ;
    use MediaWords::CommonLibs;
    extends 'MediaCloud::JobManager::Configuration';

    sub BUILD
    {
        my $self = shift;

        my $config     = MediaWords::Util::Config::get_config();
        my $job_broker = undef;

        if ( $config->{ job_manager }->{ rabbitmq } )
        {
            my $rabbitmq_config = $config->{ job_manager }->{ rabbitmq }->{ client };

            $job_broker = MediaCloud::JobManager::Broker::RabbitMQ->new(
                hostname => $rabbitmq_config->{ hostname },
                port     => $rabbitmq_config->{ port },
                username => $rabbitmq_config->{ username },
                password => $rabbitmq_config->{ password },
                vhost    => $rabbitmq_config->{ vhost },
                timeout  => $rabbitmq_config->{ timeout },
            );
        }
        elsif ( $config->{ job_manager }->{ gearman } )
        {
            my $servers = $config->{ job_manager }->{ gearman }->{ client }->{ servers };
            unless ( ref $servers eq ref [] )
            {
                LOGCONFESS "Gearman client servers is not an array.";
            }
            unless ( scalar( @{ $servers } ) > 0 )
            {
                LOGCONFESS "No Gearman client servers are configured.";
            }

            $job_broker = MediaCloud::JobManager::Broker::Gearman->new( servers => $servers );
        }

        unless ( $job_broker )
        {
            LOGCONFESS "No supported job broker is configured.";
        }

        $self->broker( $job_broker );
    }

    no Moose;    # gets rid of scaffolding

    1;
}

{

    package MediaWords::AbstractJob;

    #
    # Superclass of all Media Cloud jobs
    #

    use Moose::Role;
    with 'MediaCloud::JobManager::Job';
    use MediaWords::CommonLibs;

    use MediaWords::DB;

    # Run job
    sub run($;$)
    {
        my ( $self, $args ) = @_;

        LOGCONFESS "This is a placeholder implementation of the run() subroutine for a job.";
    }

    # Return default configuration
    sub configuration()
    {
        # It would be great to place configuration() in some sort of a superclass
        # for all the Media Cloud jobs, but Moose::Role doesn't
        # support that :(
        return MediaWords::AbstractJob::Configuration->instance;
    }

    # Whether or not RabbitMQ should create lazy queues for the jobs
    sub lazy_queue()
    {
        # When some services are stopped on production, the queues might fill
        # up pretty quickly
        return 1;
    }

    # Whether or not publish job state and return value upon completion to a
    # separate RabbitMQ queue
    sub publish_results()
    {
        # Don't create response queues and post messages with job results to
        # them because they use up resources and we don't really check those
        # results for the many jobs that we run
        return 0;
    }

    no Moose;    # gets rid of scaffolding

    # Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
    __PACKAGE__;
}
