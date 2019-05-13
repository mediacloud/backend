package MediaWords::AbstractStatefulJob;

#
# Run job while logging its state
#

use strict;
use warnings;

use Moose::Role;
with 'MediaWords::AbstractJob';

use MediaWords::CommonLibs;

use Readonly;
use Sys::Hostname;

use MediaWords::DB;
use MediaWords::DB::Locks;
use MediaWords::Util::ParseJSON;
use MediaWords::Util::SQL;
use MediaWords::JobManager::Job;

# tag to put into a die() message to make the module not set the final state to 'error' on a die (for testing)
Readonly our $DIE_WITHOUT_ERROR_TAG => 'dU3A4yUajMLV';

Readonly our $STATE_QUEUED    => 'queued';
Readonly our $STATE_RUNNING   => 'running';
Readonly our $STATE_COMPLETED => 'completed';
Readonly our $STATE_ERROR     => 'error';

# set to the job_states_id for the current job while run() is executing
my $_current_job_states_id;

# create the initial entry in the job_states table with a state of 'queued' and return the resulting
# job_states_id
sub _create_queued_job_state($$$;$)
{
    my ( $db, $class, $args, $priority ) = @_;

    my $args_json = MediaWords::Util::ParseJSON::encode_json( $args );
    $priority ||= $MediaWords::JobManager::Job::MJM_JOB_PRIORITY_NORMAL;

    my $job_state = {
        state      => $STATE_QUEUED,
        args       => $args_json,
        priority   => $priority,
        class      => $class,
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

    $db ||= MediaWords::DB::connect_to_db();
    my $job_state = _create_queued_job_state( $db, $class, $args, $priority );
    $args->{ job_states_id } = $job_state->{ job_states_id };

    eval { _update_table_state( $db, $class, $job_state ); };
    LOGCONFESS( "error updating table state: $@" ) if ( $@ );

    $class->SUPER::add_to_queue( $args, $priority );
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
sub _update_table_state($$$)
{
    my ( $db, $class, $job_state ) = @_;

    my $table_info = $class->get_state_table_info() || return;

    my $args = MediaWords::Util::ParseJSON::decode_json( $job_state->{ args } );

    my $id_field = $table_info->{ table } . '_id';
    my $id_value = $args->{ $id_field };

    # sometimes there is not a relevant <table>_id until some of the code in run() has run,
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
# from within the run() implementation of the sub class.
sub _update_job_state($$$)
{
    my ( $class, $db, $state, $message ) = @_;

    DEBUG( "$class state: $state" );

    my $job_states_id = $_current_job_states_id;
    LOGCONFESS( "must be called from inside of MediaWords::AbstractStatefulJob::run()" ) unless ( $job_states_id );

    my $job_state = $db->update_by_id(
        'job_states',
        $job_states_id,
        {
            state        => $state,
            last_updated => MediaWords::Util::SQL::sql_now(),
            message      => $message || ''
        }
    );

    _update_table_state( $db, $class, $job_state );
}

# update the args field for the current job_state row
sub update_job_state_args($$$)
{
    my ( $class, $db, $update ) = @_;

    my $job_states_id = $_current_job_states_id;
    LOGCONFESS( "must be called from inside of MediaWords::AbstractStatefulJob::run" ) unless ( $job_states_id );

    my $job_state = $db->require_by_id( 'job_states', $job_states_id );

    my $args_data = MediaWords::Util::ParseJSON::decode_json( $job_state->{ args } );

    my $json_data;
    map { $json_data->{ $_ } = $args_data->{ $_ } } ( keys( %{ $args_data } ) );
    map { $json_data->{ $_ } = $update->{ $_ } }    ( keys( %{ $update } ) );

    my $args_json = MediaWords::Util::ParseJSON::encode_json( $json_data );

    $db->update_by_id( 'job_states', $job_state->{ job_states_id }, { args => $args_json } );

}

# update the message field for the current job_state row.  this is a public method that is intended to be used
# by code run anywhere above the stack from run() to publish messages updating the progress
# of a long running job.
sub update_job_state_message($$$)
{
    my ( $class, $db, $message ) = @_;

    my $job_states_id = $_current_job_states_id;
    LOGCONFESS( "must be called from inside of MediaWords::AbstractStatefulJob::run" ) unless ( $job_states_id );

    my $job_state = $db->require_by_id( 'job_states', $job_states_id );

    $job_state = $db->update_by_id(
        'job_states',
        $job_state->{ job_states_id },
        { message => $message, last_updated => MediaWords::Util::SQL::sql_now() }
    );

    _update_table_state( $db, $class, $job_state );
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
    my ( $class ) = @_;

    return $class;
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
        if ( !MediaWords::DB::Locks::get_session_lock( $db, $lock_type, $args->{ $run_lock_arg }, 0 ) )
        {
            WARN( "Job with $run_lock_arg = $args->{ $run_lock_arg } is already running.  Exiting." );
            return;
        }
        DEBUG( "Got run once lock for this job class." );
    }

    my $r;

    eval {
        LOGCONFESS( "run() calls cannot be nested for stateful jobs" ) if ( $_current_job_states_id );

        my $job_states_id = $args->{ job_states_id };
        if ( !$job_states_id )
        {
            my $job_state = _create_queued_job_state( $db, $class, $args );
            $job_states_id = $job_state->{ job_states_id };
        }

        $_current_job_states_id = $job_states_id;

        $class->_update_job_state( $db, $STATE_RUNNING );

        $r = $class->SUPER::run( $db, $args );
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
            $class->_update_job_state( $db, $STATE_ERROR, $eval_error );
        }
        else
        {
            $class->_update_job_state( $db, $STATE_COMPLETED );
        }
    };

    $_current_job_states_id = undef;

    return $r;
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
