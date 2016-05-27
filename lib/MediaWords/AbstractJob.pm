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
                die "Gearman client servers is not an array.";
            }
            unless ( scalar( @{ $servers } ) > 0 )
            {
                die "No Gearman client servers are configured.";
            }

            $job_broker = MediaCloud::JobManager::Broker::Gearman->new( servers => $servers );
        }

        unless ( $job_broker )
        {
            die "No supported job broker is configured.";
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

    use MediaWords::DB;

    # Run job
    sub run($;$)
    {
        my ( $self, $args ) = @_;

        die "This is a placeholder implementation of the run() subroutine for a job.";
    }

    # Return default configuration
    sub configuration()
    {
        # It would be great to place configuration() in some sort of a superclass
        # for all the Media Cloud jobs, but Moose::Role doesn't
        # support that :(
        return MediaWords::AbstractJob::Configuration->instance;
    }

    no Moose;    # gets rid of scaffolding

    # Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
    __PACKAGE__;
}
