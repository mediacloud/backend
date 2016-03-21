package MediaWords::GearmanFunction;

#
# Superclass of all Media Cloud Gearman functions
#
# Provides:
#
# * default Media Cloud configuration for all Media Cloud Gearman jobs
#
# * helper subroutine gearman_is_enabled() to check whether or not Gearman is
#   configured in mediawords.yml and should be used
#
# * wrappers around enqueue_on_gearman() and run() subroutines that keep track
#   and permanently log the Gearman job status in the database (because
#   Gearman is unable to do that itself :-()
#

use strict;
use warnings;

use Moose::Role;
with 'Gearman::JobScheduler::AbstractFunction';

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::DB;
use MediaWords::Util::Config;
use Gearman::JobScheduler;
use MediaWords::Util::GearmanJobSchedulerConfiguration;

# (Gearman::JobScheduler::AbstractFunction implementation) Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    die "This is a placeholder implementation of the run() subroutine for the Gearman function.";
}

sub _insert_job_if_does_not_exist($$$$)
{
    my ( $db, $function_name, $job_handle, $unique_job_id ) = @_;

    # Vanilla INSERTing a job handle into "gearman_job_queue" right after
    # enqueueing the job on Gearman would have some potential for race
    # condition.

    # For example, a Gearman worker might start the job and try to UPDATE
    # "gearman_job_queue" before enqueue_on_gearman() even finished its INSERT.
    #
    # Therefore, this subroutine is being run two times (once after
    # enqueue_on_gearman(), another time right before run()) to make sure that
    # a Gearman job exists in the table with the correct handle.

    say STDERR "Writing job handle '$job_handle' to database.";

    $db->query(
        <<EOF,
        INSERT INTO gearman_job_queue (function_name, job_handle, unique_job_id, status)
            SELECT ?, ?, ?, 'enqueued'
            WHERE NOT EXISTS (
                SELECT 1
                FROM gearman_job_queue
                WHERE job_handle = ?
            )
EOF
        $function_name, $job_handle, $unique_job_id, $job_handle
    );

}

# INSERT a new job in the "gearman_job_queue" table after enqueueing the job
around 'enqueue_on_gearman' => sub {
    my $orig = shift;
    my $self = shift;

    my $args;
    if ( scalar @_ )
    {
        $args = $_[ 0 ];
    }

    my $db = MediaWords::DB::connect_to_db;

    # Enqueue the job
    my $job_handle    = $self->$orig( @_ );
    my $function_name = $self . '';
    my $unique_job_id = Gearman::JobScheduler::unique_job_id( $function_name, $args );
    unless ( $unique_job_id )
    {
        die "Unable to generate an unique job ID for Gearman function '$function_name'";
    }

    # Log in the database
    if ( $job_handle )
    {

        # Successfully enqueued
        _insert_job_if_does_not_exist( $db, $function_name, $job_handle, $unique_job_id );

    }
    else
    {

        # Failed to enqueue
        $db->query(
            <<EOF,
            INSERT INTO gearman_job_queue (function_name, job_handle, unique_job_id, status, error_message)
            VALUES (?, ?, ?, 'enqueued', 'Unable to get Gearman job handle.')
EOF
            $function_name, $job_handle, $unique_job_id
        );

    }

    return $job_handle;
};

# Warning
before 'run_on_gearman' => sub {

    say STDERR <<EOF
        Please note that calls on run_on_gearman() are not logged in
        'gearman_job_queue' database table because there is no sensible way to
        get hold of the Gearman job handle in this subroutine.
EOF
};

# Try running the job (in the worker) and UPDATE status in "gearman_job_queue"
# accordingly
around 'run' => sub {
    my $orig = shift;
    my $self = shift;

    my $args;
    if ( scalar @_ )
    {
        $args = $_[ 0 ];
    }

    my $ret_value = undef;

    if ( defined $self->_gearman_job )
    {

        my $db = MediaWords::DB::connect_to_db;

        my $job_handle    = $self->_gearman_job->handle();
        my $function_name = $self . '';
        my $unique_job_id = Gearman::JobScheduler::unique_job_id( $function_name, $args );
        unless ( $unique_job_id )
        {
            die "Unable to generate an unique job ID for Gearman function '$function_name'";
        }

        # Make sure the job is enqueued at this point
        _insert_job_if_does_not_exist( $db, $function_name, $job_handle, $unique_job_id );

        # Set state to "running"
        $db->query(
            <<EOF,
            UPDATE gearman_job_queue
            SET status = 'running'
            WHERE job_handle = ?
EOF
            $job_handle
        );

        eval {
            # Try running the job
            $ret_value = $self->$orig( @_ );
        };
        if ( $@ )
        {

            # Error
            my $message = $@;
            $db->query(
                <<EOF,
                UPDATE gearman_job_queue
                SET status = 'failed', error_message = ?
                WHERE job_handle = ?
EOF
                $message, $job_handle
            );
            die( "MediaWords Gearman job '$job_handle' failed: $message" );

        }
        else
        {
            # Success
            $db->query(
                <<EOF,
                UPDATE gearman_job_queue
                SET status = 'finished'
                WHERE job_handle = ?
EOF
                $job_handle
            );
        }

    }
    else
    {

        # Job is being run as run_locally() or run_on_gearman()
        say STDERR "Running the job locally, Gearman doesn't have anything to do with this run";
        $ret_value = $self->$orig( @_ );

    }

    return $ret_value;
};

# (Gearman::JobScheduler::AbstractFunction implementation) Return default configuration
sub configuration()
{
    # It would be great to place configuration() in some sort of a superclass
    # for all the Media Cloud Gearman functions, but Moose::Role doesn't
    # support that :(
    return MediaWords::Util::GearmanJobSchedulerConfiguration->instance;
}

# (Media Cloud-only helper) Return 1 if Gearman is configured and enabled
sub gearman_is_enabled()
{
    # Enabled when there is at least one configured Gearman server
    my $config = MediaWords::Util::Config::get_config();
    return defined $config->{ gearman }->{ servers };
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
