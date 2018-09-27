use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::Util::Config;

use MediaWords::DB::Locks;

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
    with 'MediaCloud::JobManager::Job' => {

        # this alias magic is required to be able to override the MediaCloud::JobManager::Job::add_to_queue
        # helper function -- it reassigns that helper function to $class->_role_add_to_queue so that
        # we can define our own $class->add_to_queue()
        -alias    => { add_to_queue => '_role_add_to_queue' },
        -excludes => [ 'add_to_queue' ]
    };

    use MediaWords::CommonLibs;

    use Readonly;
    use Sys::Hostname;

    use MediaWords::DB;
    use MediaWords::Util::ParseJSON;

    # tag to put into a die() message to make the module not set the final state to 'error' on a die (for testing)
    Readonly our $DIE_WITHOUT_ERROR_TAG => 'dU3A4yUajMLV';

    Readonly our $STATE_QUEUED    => 'queued';
    Readonly our $STATE_RUNNING   => 'running';
    Readonly our $STATE_COMPLETED => 'completed';
    Readonly our $STATE_ERROR     => 'error';

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

        my $args_json = MediaWords::Util::ParseJSON::encode_json( $args );
        $priority ||= $MediaCloud::JobManager::Job::MJM_JOB_PRIORITY_NORMAL;

        my $job_state = {
            state      => $STATE_QUEUED,
            args       => $args_json,
            priority   => $priority,
            class      => $self->name(),
            process_id => $$,
            hostname   => Sys::Hostname::hostname
        };

        $job_state = $db->create( 'job_states', $job_state );

        return $job_state;
    }

    # override add_to_queue method to add state actions, including add a new job_states row with a state
    # of $STATE_QUEUED. optinoally include a $db handle to use to create the job_states row
    sub add_to_queue($;$$$)
    {
        my ( $class, $args, $priority, $db ) = @_;

        if ( $class->use_job_state() )
        {
            $db ||= MediaWords::DB::connect_to_db();
            my $job_state = $class->_create_queued_job_state( $db, $args, $priority );
            $args->{ job_states_id } = $job_state->{ job_states_id };

            eval { $class->_update_table_state( $db, $job_state ); };
            LOGCONFESS( "error updating table state: $@" ) if ( $@ );
        }

        $class->_role_add_to_queue( $args, $priority );
    }

    # sub classes that use job state should implement run_statefully() intead of run() to make sure that
    # job state always gets set on job start, finish, and error.  unlike run(), run_statefully() will be provided
    # with a $db handle as an argument.
    sub run_statefully($$;$)
    {
        my ( $self, $db, $args ) = @_;

        LOGCONFESS( "classes that return true for use_job_states() must implement run_statefully() or run()" );
    }

    # return the job_states row associated with the currently running job
    sub get_current_job_state($$)
    {
        my ( $self, $db ) = @_;

        LOGDIE( "no stateful job is currently running" ) unless ( $_current_job_states_id );

        return $db->require_by_id( 'job_states', $_current_job_states_id );
    }

    # to make update_job_state() update a state field in a table other than job_states, make this method return a
    # hash in the form of { table => $table, state_field => $state_field, message_field => $message_field }.  this is
    # useful to keep the state and message of the current job in a table for easy access, for instance in
    # topics.state for the MineTopic job.
    sub get_state_table_info($)
    {
        return undef;
    }

    # if get_state_table_info() returns a value, update the state and message fields in the given table for the
    # row whose '<table>_id' field matches that field in the job args
    sub _update_table_state($$$;$)
    {
        my ( $self, $db, $job_state ) = @_;

        my $table_info = $self->get_state_table_info() || return;

        my $args = MediaWords::Util::ParseJSON::decode_json( $job_state->{ args } );

        my $id_field = $table_info->{ table } . '_id';
        my $id_value = $args->{ $id_field };

        # sometimes there is not a relevant <table>_id until some of the code in run_statefully() has run,
        # for instance SnapshotTopic needs to create the snapshot.
        return unless ( $id_value );

        my $update = {
            $table_info->{ state }   => $job_state->{ state },
            $table_info->{ message } => $job_state->{ message }
        };

        $db->update_by_id( $table_info->{ table }, $id_value, $update );
    }

    # update the state and message fields of the job_states table for the currently active job_states_id.
    # jobs_states_id is set and unset in sub run() below, so this must be called from code running
    # from within the run_statefully() implementation of the sub class.
    sub _update_job_state($$$)
    {
        my ( $self, $db, $state, $message ) = @_;

        DEBUG( $self->name . " state: $state" );

        my $job_states_id = $_current_job_states_id;
        LOGCONFESS( "must be called from inside of MediaWords::AbstractJob::run_statefully" ) unless ( $job_states_id );

        my $job_state = $db->update_by_id(
            'job_states',
            $job_states_id,
            {
                state        => $state,
                last_updated => MediaWords::Util::SQL::sql_now(),
                message      => $message || ''
            }
        );

        $self->_update_table_state( $db, $job_state );
    }

    # update the args field for the current job_state row
    sub update_job_state_args($$$)
    {
        my ( $self, $db, $update ) = @_;

        my $job_states_id = $_current_job_states_id;
        LOGCONFESS( "must be called from inside of MediaWords::AbstractJob::run_statefully" ) unless ( $job_states_id );

        my $job_state = $db->require_by_id( 'job_states', $job_states_id );

        my $args_data = MediaWords::Util::ParseJSON::decode_json( $job_state->{ args } );

        map { $args_data->{ $_ } = $update->{ $_ } } ( keys( %{ $update } ) );

        my $args_json = MediaWords::Util::ParseJSON::encode_json( $args_data );

        $db->update_by_id( 'job_states', $job_state->{ job_states_id }, { args => $args_json } );

    }

    # update the message field for the current job_state row.  this is a public method that is intended to be used
    # by code run anywhere above the stack from run_statefully() to publish messages updating the progress
    # of a long running job.
    sub update_job_state_message($$$)
    {
        my ( $self, $db, $message ) = @_;

        my $job_states_id = $_current_job_states_id;
        LOGCONFESS( "must be called from inside of MediaWords::AbstractJob::run_statefully" ) unless ( $job_states_id );

        my $job_state = $db->require_by_id( 'job_states', $job_states_id );

        $job_state = $db->update_by_id( 'job_states', $job_state->{ job_states_id }, { message => $message } );

        $self->_update_table_state( $db, $job_state );
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

    # set job state to $STATE_RUNNING, call run_statefully, either catch any errors and set state to $STATE_ERROR and save
    # the error or set state to $STATE_COMPLETED
    sub run($;$)
    {
        my ( $self, $args ) = @_;

        my $db = MediaWords::DB::connect_to_db();

        # if a job for a run locked class is already running, exit without doinig anything.
        if ( my $run_lock_arg = $self->get_run_lock_arg() )
        {
            my $lock_type = $self->get_run_lock_type();
            if ( !MediaWords::DB::Locks::get_session_lock( $db, $lock_type, $args->{ $run_lock_arg }, 0 ) )
            {
                WARN( "Job with $run_lock_arg = $args->{ $run_lock_arg } is already running.  Exiting." );
                return;
            }
            DEBUG( "Got run once lock for this job class." );
        }

        my $r;

        eval {
            LOGCONFESS( "run() must be defined unless use_job_state() returns true" ) unless ( $self->use_job_state() );

            LOGCONFESS( "run() calls cannot be nested for stateful jobs" ) if ( $_current_job_states_id );

            my $job_states_id = $args->{ job_states_id };
            if ( !$job_states_id )
            {
                my $job_state = $self->_create_queued_job_state( $db, $args );
                $job_states_id = $job_state->{ job_states_id };
            }

            $_current_job_states_id = $job_states_id;

            $self->_update_job_state( $db, $STATE_RUNNING );

            $r = $self->run_statefully( $db, $args );
        };

        my $eval_error = $@;

        if ( $eval_error && ( $eval_error =~ /\Q$DIE_WITHOUT_ERROR_TAG\E/ ) )
        {
            # do nothing -- this is to be able to test the module
            $_current_job_states_id = undef;
            return $r;
        }

        # eval this so that we are sure that the $_current_job_states_id reset below happens
        eval {
            if ( $eval_error )
            {
                WARN( "logged error in job_states: $eval_error" );
                $self->_update_job_state( $db, $STATE_ERROR, $eval_error );
            }
            else
            {
                $self->_update_job_state( $db, $STATE_COMPLETED );
            }
        };

        $_current_job_states_id = undef;

        return $r;
    }

    no Moose;    # gets rid of scaffolding

    # Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
    __PACKAGE__;
}
