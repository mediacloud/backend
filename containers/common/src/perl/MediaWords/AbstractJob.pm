package MediaWords::AbstractJob;

#
# Superclass of all Media Cloud jobs
#

use strict;
use warnings;

use Moose::Role;
with 'MediaWords::JobManager::Job';

use MediaWords::CommonLibs;

use Readonly;

use MediaWords::DB;
use MediaWords::DB::Locks;
use MediaWords::Util::ParseJSON;
use MediaWords::Util::Config::Common;

# (static) Return broker used the job manager
sub broker()
{
    my $rabbitmq_config = MediaWords::Util::Config::Common::rabbitmq();

    my $job_broker = MediaWords::JobManager::Broker::RabbitMQ->new(
        hostname => $rabbitmq_config->hostname(),
        port     => $rabbitmq_config->port(),
        username => $rabbitmq_config->username(),
        password => $rabbitmq_config->password(),
        vhost    => $rabbitmq_config->vhost(),
        timeout  => $rabbitmq_config->timeout(),
    );

    unless ( $job_broker )
    {
        LOGCONFESS "No supported job broker is configured.";
    }

    return $job_broker;
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

# define this in the sub class to make it so that only one job can run for each distinct value of the
# given $arg.  For instance, set this to 'topics_id' to make sure that only one MineTopic job can be running
# at a given time for a given topics_id.
sub get_run_lock_arg()
{
    return undef;
}

# return the lock type from mediawords.db.locks to use for run once locking.  default to the class name.
sub get_run_lock_type()
{
    my ( $self ) = @_;

    return ref( $self );
}

# set job state to $STATE_RUNNING, call run(), either catch any errors and set state to $STATE_ERROR and save
# the error or set state to $STATE_COMPLETED
sub run($;$)
{
    my ( $class, $args ) = @_;

    my $db = MediaWords::DB::connect_to_db();

    # if a job for a run locked class is already running, exit without doinig anything.
    if ( my $run_lock_arg = $class->get_run_lock_arg() )
    {
        my $lock_type = $class->get_run_lock_type();
        unless ( MediaWords::DB::Locks::get_session_lock( $db, $lock_type, $args->{ $run_lock_arg }, 0 ) )
        {
            WARN( "Job with $run_lock_arg = $args->{ $run_lock_arg } is already running.  Exiting." );
            return;
        }
        DEBUG( "Got run once lock for this job class." );
    }

    return $class->SUPER::run( $args );
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
