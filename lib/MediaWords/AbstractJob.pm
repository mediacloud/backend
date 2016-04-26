use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::Util::Config;

{

    package MediaWords::AbstractJob::Configuration;

    #
    # Implements Gearman::JobScheduler::Configuration with values from Media Cloud's configuration
    #

    use Moose;
    use Gearman::JobScheduler::Configuration;
    extends 'Gearman::JobScheduler::Configuration';

    # Media Cloud configuration
    has 'mc_config' => ( is => 'rw' );

    sub BUILD
    {
        my $self = shift;

        # Read configuration
        $self->mc_config( MediaWords::Util::Config::get_config() );
    }

    # Default Gearman servers to connect to
    override 'gearman_servers' => sub {
        my $self = shift;

        return $self->mc_config->{ gearman }->{ servers };
    };

    # Where should the worker put the logs
    override 'worker_log_dir' => sub {
        my $self = shift;

        return $self->mc_config->{ gearman }->{ worker_log_dir } // $self->SUPER::worker_log_dir();
    };

    # Default email address to send the email from
    override 'notifications_from_address' => sub {
        my $self = shift;

        return $self->mc_config->{ gearman }->{ notifications }->{ from_address }
          // $self->SUPER::notifications_from_address();
    };

    # Notification email subject prefix
    override 'notifications_subject_prefix' => sub {
        my $self = shift;

        return $self->mc_config->{ gearman }->{ notifications }->{ subject_prefix }
          // $self->SUPER::notifications_subject_prefix();
    };

    # Emails that should receive notifications about failed jobs
    override 'notifications_emails' => sub {
        my $self = shift;

        return $self->mc_config->{ gearman }->{ notifications }->{ emails } // $self->SUPER::notifications_emails();
    };

    no Moose;    # gets rid of scaffolding

    1;
}

{

    package MediaWords::AbstractJob;

    #
    # Superclass of all Media Cloud jobs
    #

    use Moose::Role;
    with 'Gearman::JobScheduler::AbstractFunction';

    use MediaWords::DB;
    use Gearman::JobScheduler;

    # (Gearman::JobScheduler::AbstractFunction implementation) Run job
    sub run($;$)
    {
        my ( $self, $args ) = @_;

        die "This is a placeholder implementation of the run() subroutine for the Gearman function.";
    }

    # (Gearman::JobScheduler::AbstractFunction implementation) Return default configuration
    sub configuration()
    {
        # It would be great to place configuration() in some sort of a superclass
        # for all the Media Cloud Gearman functions, but Moose::Role doesn't
        # support that :(
        return MediaWords::AbstractJob::Configuration->instance;
    }

    no Moose;    # gets rid of scaffolding

    # Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
    __PACKAGE__;
}
