package MediaWords::JobManager::Configuration;

#
# Default configuration
#

use strict;
use warnings;
use Modern::Perl "2012";

use Moose 2.1005;
use MooseX::Singleton;    # ->instance becomes available
use MediaWords::JobManager::Job;
use MediaWords::JobManager::Broker;
use MediaWords::JobManager::Broker::Null;
use MediaWords::JobManager::Broker::RabbitMQ;

# Instance of specific job broker
has 'broker' => (
    is      => 'rw',
    isa     => 'MediaWords::JobManager::Broker',
    default => sub { return MediaWords::JobManager::Broker::Null->new(); },
);

no Moose;    # gets rid of scaffolding

1;
