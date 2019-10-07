package MediaWords::JobManager::Job;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use feature qw(switch);

use Moose::Role 2.1005;

use MediaWords::JobManager::AbstractJob;
use MediaWords::JobManager::Priority;

use Time::HiRes;
use Data::Dumper;
use DateTime;
use Readonly;

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

sub __run($;$)
{
    my ( $function_name, $args ) = @_;

    my $broker = MediaWords::JobManager::AbstractJob::broker();

    my $result;
    eval {

        my $d = Data::Dumper->new( [ $args ], [ 'args' ] );
        $d->Indent( 0 );
        $d->Sortkeys( 1 );

        my $str_arguments = $d->Dump;

        INFO( "Starting job..." );
        INFO( "========" );
        INFO( "Arguments: $str_arguments" );
        INFO( "========" );
        INFO( "" );

        my $start = Time::HiRes::gettimeofday();

        eval {

            # Try to run the job
            my $instance = $function_name->new();

            # Do the work
            $result = $instance->run( $args );

            # Destroy instance
            $instance = undef;
        };

        if ( $@ )
        {
            ERROR( "" );
            ERROR( "========" );
            LOGDIE( "Job failed: $@" );
        }

        my $end = Time::HiRes::gettimeofday();

        INFO( "" );
        INFO( "========" );
        INFO( "Finished job in " . sprintf( "%.2f", $end - $start ) . " seconds" );

    };

    my $error = $@;
    if ( $@ )
    {
        LOGDIE( "Job died: $error" );
    }

    return $result;
}

sub run_locally($;$)
{
    my ( $function_name, $args ) = @_;

    unless ( $function_name )
    {
        LOGDIE( "Unable to determine function name." );
    }

    my $job_result;
    eval { $job_result = $function_name->__run( $args ); };
    my $error_message = $@;

    if ( $error_message ) {
        ERROR( "Local job died: $@" );        
    }

    return $job_result;
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

    my $broker = MediaWords::JobManager::AbstractJob::broker();

    $priority //= $MediaWords::JobManager::Priority::MJM_JOB_PRIORITY_NORMAL;
    unless ( MediaWords::JobManager::Priority::priority_is_valid( $priority ) )
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

    my $broker = MediaWords::JobManager::AbstractJob::broker();

    $priority //= $MediaWords::JobManager::Priority::MJM_JOB_PRIORITY_NORMAL;
    unless ( MediaWords::JobManager::Priority::priority_is_valid( $priority ) )
    {
        LOGDIE( "Job priority '$priority' is not valid." );
    }

    return $broker->run_job_async( $function_name, $args, $priority );
}

no Moose;    # gets rid of scaffolding

1;
