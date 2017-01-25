use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::Test::Supervisor;
use MediaWords::Util::Config;

{

    package MediaWords::AbstractJob::Configuration;

    #
    # Implements MediaCloud::JobManager::Configuration with values from Media Cloud's configuration
    #

    use Moose;
    use MediaCloud::JobManager::Configuration;
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

    use Readonly;
    use Sys::Hostname;

    use MediaWords::DB;
    use MediaWords::Util::JSON;

    # tag to put into a die() message to make the module not set the final
    # state to 'error' on a die for testing
    Readonly our $DIE_WITHOUT_ERROR_TAG => 'dU3A4yUajMLV';

    # set to the job_states_id for the current job while run_statefully() is executing
    my $_current_job_states_id;

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

    # return true if jobs run through the sub class should maintain state in the job_states
    # table for every job run. state maintenance is relatively expensive
    # (it requires inserting and updating multiple times a row for every job), so it should
    # be used only for relatively long lived jobs.
    sub use_job_state
    {
        return 0;
    }

    # create the initial entry in the job_states table with a state of 'queued' and return the resulting
    # job_states_id
    sub _create_queued_job_state($$$;$)
    {
        my ( $self, $db, $args, $priority ) = @_;

        my $args_json = MediaWords::Util::JSON::encode_json( $args );
        $priority ||= $MediaCloud::JobManager::Job::MJM_JOB_PRIORITY_NORMAL;

        my $job_state = {
            state      => 'queued',
            args       => $args_json,
            priority   => $priority,
            class      => $self->name(),
            process_id => $$,
            hostname   => Sys::Hostname::hostname
        };

        $job_state = $db->create( 'job_states', $job_state );

        return $job_state->{ job_states_id };
    }

    ## override add_to_queue method to add state actions
    sub add_to_queue($$;$)
    {
        my ( $self, $args, $priority ) = @_;

        if ( $self->use_job_state() )
        {
            my $db = MediaWords::DB::connect_to_db();
            my $job_states_id = $self->_create_queued_job_state( $db, $args, $priority );
            $args->{ job_states_id } = $job_states_id;
        }

        $self->SUPER::add_to_queue( $args, $priority );
    }

    # sub classes that use jbo state should implement run_statefully intead of run() to make sure that
    # job state always gets set on job start, finish, and error.  unlike run(), run_statefully will be provided
    # with a $db handle as an argument.
    sub run_statefully($$;$)
    {
        my ( $self, $db, $args ) = @_;

        LOGCONFESS( "classes that return true for use_job_states() must implement run_statefully() or run()" );
    }

    # update the 'state' field of the job_states table for the currently active job_states_id.
    # jobs_states_id is set and unset in sub run() below, so this must be called from code running
    # from within the run_statefully() implementation of the sub class.
    sub update_job_state($$$)
    {
        my ( $self, $db, $state, $message ) = @_;

        my $job_states_id = $_current_job_states_id;
        LOGCONFESS( "must be called from inside of MediaWords::AbstractJob::run_statefully" ) unless ( $job_states_id );

        $db->update_by_id(
            'job_states',
            $job_states_id,
            {
                state        => $state,
                last_updated => MediaWords::Util::SQL::sql_now(),
                message      => $message || ''
            }
        );
    }

    # set job state to running, call run_statefully, either catch any errors and set state to error and save
    # the error or set state to 'completed successfully'
    sub run($;$)
    {
        my ( $self, $args ) = @_;

        LOGCONFESS( "run() must be defined unless use_job_state() returns true" ) unless ( $self->use_job_state() );

        LOGCONFESS( "run() calls cannot be nested for stateful jobs" ) if ( $_current_job_states_id );

        my $db = MediaWords::DB::connect_to_db();

        my $job_states_id = $args->{ job_states_id } || $self->_create_queued_job_state( $db, $args );

        $_current_job_states_id = $job_states_id;

        $self->update_job_state( $db, 'running' );

        my $r = eval { $self->run_statefully( $db, $args ) };

        if ( $@ && ( $@ =~ /\Q$DIE_WITHOUT_ERROR_TAG\E/ ) )
        {
            # do nothing -- this is to be able to test the module
        }
        elsif ( $@ )
        {
            WARN( "logged error in job_states: $@" );
            $self->update_job_state( $db, 'error', $@ );
        }
        else
        {
            $self->update_job_state( $db, 'completed successfully' );
        }

        $_current_job_states_id = undef;

        return $r;
    }

    no Moose;    # gets rid of scaffolding

    # Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
    __PACKAGE__;
}
