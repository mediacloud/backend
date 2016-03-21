package MediaWords::Util::GearmanJobSchedulerConfiguration;

#
# implements Gearman::JobScheduler::Configuration with values from Media Cloud's configuration
#

use strict;
use warnings;

use Moose;
use Gearman::JobScheduler::Configuration;
extends 'Gearman::JobScheduler::Configuration';

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::Util::Config;

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

    return $self->mc_config->{ gearman }->{ notifications }->{ from_address } // $self->SUPER::notifications_from_address();
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

