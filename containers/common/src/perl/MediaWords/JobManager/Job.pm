
=head1 NAME

C<MediaWords::JobManager::Job> - An abstract class for a "function".


=head1 LINGO

=over 4

=item * function

A function to be run by locally or remotely, e.g. C<add_default_feeds>.

=item * job

An instance of the function doing the actual job with specific parameters.

=back

=cut

package MediaWords::JobManager::Job;

use strict;
use warnings;
use Modern::Perl "2015";
use feature qw(switch);

use Moose::Role 2.1005;

use MediaWords::JobManager;    # helper subroutines
use MediaWords::AbstractJob;

use Time::HiRes;
use Data::Dumper;
use DateTime;
use Readonly;

# used for capturing STDOUT and STDERR output of each job and timestamping it;
# initialized before each job
use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init(
    {
        level  => $DEBUG,
        utf8   => 1,
        layout => "%d{ISO8601} [%P]: %m%n"
    }
);

=head1 ABSTRACT INTERFACE

The following subroutines must be implemented by the subclasses of this class.

=head2 REQUIRED

=head3 C<run($self, $args)>

Run the job.

Parameters:

=over 4

=item * C<$self>, a reference to the instance of the function class

=item * (optional) C<$args> (hashref), arguments needed for running the
function

=back

An instance (object) of the class will be created before each run. Class
instance variables (e.g. C<$self-E<gt>_my_variable>) will be discarded after
each run.

Returns result on success (serializable by the L<JSON> module). The result will
be discarded if the job is added as a background process.

C<die()>s on error.

Writes log to C<STDOUT> or C<STDERR> (preferably the latter).

=cut

requires 'run';

=head2 OPTIONAL

=head3 (static) C<retries()>

Return the number of retries for each job.

Returns a number of retries each job will be attempted at. For example, if the
number of retries is set to 3, the job will be attempted 4 four times in total.

Returns 0 if the job should not be retried (attempted only once).

Default implementation of this subroutine returns 0 (no retries).

=cut

sub retries()
{
    # By default the job will not be retried if it fails
    return 0;
}

=head3 (static) C<lazy_queue()>

Return true if RabbitMQ should create a "lazy" queue for this function.

Returns true if the job queue is expected to grow very large so RabbitMQ should
create a "lazy" queue (https://www.rabbitmq.com/lazy-queues.html) for this type
of job.

Default implementation of this subroutine returns 0 ("default" type of queue).

=cut

sub lazy_queue()
{
    return 1;
}

=head3 (static) C<publish_results()>

Return true if worker should publish results back to a results RabbitMQ queue.

Returns true if client that added job to the queue might be interested in the
results of the job (whether or not it has failed, what has run() returned) so
RabbitMQ should keep a result of the job and send it back to client when
requested.

One might want to disable this if distinct results of many jobs aren't that
important and you'd like to make job broker a little bit faster.

This subroutine will only be used when calling add_to_queue().

Default implementation of this subroutine returns 1 (results will be collected,
stored and sent back to clients if requested).

=cut

sub publish_results()
{
    return 1;
}

=head3 Priorities

Jobs in a single queue can have different priorities ("low", "normal" or
"high") in order for them to be run in desirable order:

=over 4

=item * C<$MJM_JOB_PRIORITY_LOW>, if the job is considered of "low priority".

=item * C<$MJM_JOB_PRIORITY_NORMAL> if the job is considered of "normal priority".

=item * C<$MJM_JOB_PRIORITY_HIGH> if the job is considered of "high priority".

=back

C<run_remotely()> and C<add_to_queue()> both accept the job priority argument.

By default, jobs are being run with a "normal" priority.

=cut

# Job priorities
Readonly our $MJM_JOB_PRIORITY_LOW    => 'low';
Readonly our $MJM_JOB_PRIORITY_NORMAL => 'normal';
Readonly our $MJM_JOB_PRIORITY_HIGH   => 'high';

# Subroutines for backwards compatibility
sub MJM_JOB_PRIORITY_LOW    { return $MJM_JOB_PRIORITY_LOW }
sub MJM_JOB_PRIORITY_NORMAL { return $MJM_JOB_PRIORITY_NORMAL }
sub MJM_JOB_PRIORITY_HIGH   { return $MJM_JOB_PRIORITY_HIGH }

Readonly my %valid_priorities => (
    $MJM_JOB_PRIORITY_LOW    => 1,
    $MJM_JOB_PRIORITY_NORMAL => 1,
    $MJM_JOB_PRIORITY_HIGH   => 1,
);

sub _priority_is_valid($)
{
    my $priority = shift;
    return exists $valid_priorities{ $priority };
}

sub __run($;$$)
{
    my ( $function_name, $args, $job ) = @_;

    my $broker = MediaWords::AbstractJob::broker();

    # DEBUG( "Running locally" );

    my $mjm_job_id;
    if ( $job )
    {
        my $job_id = $broker->job_id_from_handle( $job );
        $mjm_job_id = MediaWords::JobManager::_unique_path_job_id( $function_name, $args, $job_id );
    }
    else
    {
        $mjm_job_id = MediaWords::JobManager::_unique_path_job_id( $function_name, $args );
    }
    unless ( $mjm_job_id )
    {
        LOGDIE( "Unable to determine unique MediaWords::JobManager job ID" );
    }

    my $result;
    eval {

        my $d = Data::Dumper->new( [ $args ], [ 'args' ] );
        $d->Indent( 0 );
        $d->Sortkeys( 1 );

        my $str_arguments = $d->Dump;

        INFO( "Starting job ID \"$mjm_job_id\"..." );
        INFO( "========" );
        INFO( "Arguments: $str_arguments" );
        INFO( "========" );
        INFO( "" );

        my $start = Time::HiRes::gettimeofday();

        my $job_succeeded = 0;
        for ( my $retry = 0 ; $retry <= $function_name->retries() ; ++$retry )
        {
            if ( $retry > 0 )
            {
                INFO( "" );
                INFO( "========" );
                INFO( "Retrying ($retry)..." );
                INFO( "========" );
                INFO( "" );
            }

            eval {

                # Try to run the job
                my $instance = $function_name->new();

                # Do the work
                $result = $instance->run( $args );

                # Destroy instance
                $instance = undef;

                $job_succeeded = 1;
            };

            if ( $@ )
            {
                ERROR( "Job \"$mjm_job_id\" failed: $@" );
            }
            else
            {
                last;
            }
        }

        unless ( $job_succeeded )
        {
            ERROR( "" );
            ERROR( "========" );
            LOGDIE( "Job \"$mjm_job_id\" failed" .
                  ( $function_name->retries() ? " after " . $function_name->retries() . " retries" : "" ) . ": $@" );
        }

        my $end = Time::HiRes::gettimeofday();

        INFO( "" );
        INFO( "========" );
        INFO( "Finished job ID \"$mjm_job_id\" in " . sprintf( "%.2f", $end - $start ) . " seconds" );

    };

    my $error = $@;
    if ( $@ )
    {
        LOGDIE( "Job died: $error" );
    }

    return $result;
}

=head1 CLIENT SUBROUTINES

The following subroutines can be used by clients to run a function.

=head2 (static) C<$function_name-E<gt>run_remotely([$args])>

Run remotely, wait for the task to complete, return the result; block the
process until the job is complete.

Parameters:

=over 4

=item * (optional) C<$args> (hashref), arguments needed for running the
function (serializable by the L<JSON> module)

=back

Returns result (may be false of C<undef>) on success, C<die()>s on error

=cut

sub run_remotely($;$$)
{
    my ( $function_name, $args, $priority ) = @_;

    unless ( $function_name )
    {
        LOGDIE( "Unable to determine function name." );
    }

    my $broker = MediaWords::AbstractJob::broker();

    $priority //= $MJM_JOB_PRIORITY_NORMAL;
    unless ( _priority_is_valid( $priority ) )
    {
        LOGDIE( "Job priority '$priority' is not valid." );
    }

    return $broker->run_job_sync( $function_name, $args, $priority );
}

=head2 (static) C<$function_name-E<gt>add_to_queue([$args])>

Add to queue remotely, do not wait for the task to complete, return
immediately; do not block the parent process until the job is complete.

Parameters:

=over 4

=item * (optional) C<$args> (hashref), arguments needed for running the
function (serializable by the L<JSON> module)

=back

Returns job ID if the job was added to queue successfully, C<die()>s on error.

=cut

sub add_to_queue($;$$)
{
    my ( $function_name, $args, $priority ) = @_;

    unless ( $function_name )
    {
        LOGDIE( "Unable to determine function name." );
    }

    my $broker = MediaWords::AbstractJob::broker();

    $priority //= $MJM_JOB_PRIORITY_NORMAL;
    unless ( _priority_is_valid( $priority ) )
    {
        LOGDIE( "Job priority '$priority' is not valid." );
    }

    return $broker->run_job_async( $function_name, $args, $priority );
}

no Moose;    # gets rid of scaffolding

1;
