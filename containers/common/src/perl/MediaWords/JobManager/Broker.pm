package MediaWords::JobManager::Broker;

#
# Abstract job broker
#

use strict;
use warnings;
use Modern::Perl "2012";

use Moose::Role;

=head2 C<$self-E<gt>start_worker($function_name)>

Start a worker.

Should call C<$function_name-E<gt>run_locally( $args, $job )> to do the actual
work. C<$job> is job handle or identifier used by helpers (e.g.
C<set_job_progress()>).

Parameters:

=over 4

=item * Function name (e.g. "NinetyNineBottlesOfBeer")

=back

=cut

requires 'start_worker';

=head2 C<$self-E<gt>run_job_sync($function_name, $args, $priority)>

Run a job synchronously (wait for the job to complete and return the result).

Parameters:

=over 4

=item * Function name (e.g. "NinetyNineBottlesOfBeer")

=item * Hashref with arguments or undef

=back

Returns job result (whatever the job subroutine returned).

=cut

requires 'run_job_sync';

=head2 C<$self-E<gt>run_job_async($function_name, $args, $priority)>

Run a job asynchronously (add job to the job queue and return instantly).

Parameters:

=over 4

=item * Function name (e.g. "NinetyNineBottlesOfBeer")

=item * Hashref with arguments or undef

=back

Returns string job ID that can be used to track the job.

=cut

requires 'run_job_async';

=head2 C<$self-E<gt>job_id_from_handle($job)>

Return string job identifier for handle.

Parameters:

=over 4

=item * Job handle or identifier

=back

=cut

requires 'job_id_from_handle';

=head2 C<$self-E<gt>set_job_progress($job, $numerator, $denominator)>

Provide progress report while running the task (from C<run()>).

Examples:

=over 4

=item * C<$self-E<gt>set_progress(3, 10)>

3 out of 10 subtasks are complete.

=item * C<$self-E<gt>set_progress(45, 100)>

45 out of 100 subtasks are complete (or 45% complete).

=back

Parameters:

=over 4

=item * Job handle or identifier

=item * Numerator

=item * Denominator

=back

=cut

requires 'set_job_progress';

=head2 C<$self-E<gt>job_status($function_name, $job_id)>

Get job status.

Parameters:

=over 4

=item * Class instance ("self")

=item * Function name (e.g. "NinetyNineBottlesOfBeer")

=item * Job ID (e.g. "H:localhost.localdomain:8")

=back

Returns array with job status:

=begin text

{     # Job ID that was passed as a parameter     'job_id' =>
'H:tundra.home:8',

    # Whether or not the job is currently running
    'running' => 1,

    # Numerator and denominator of the job's progress
    # (in this example, job is 1333/2000 complete)
    'numerator' => 1333,
    'denominator' => 2000
};

=end text

Returns undef if the job ID was not found; dies on error.

=cut

requires 'job_status';

=head2 C<$self-E<gt>show_jobs()>

Show all jobs on all the configured servers.

Returns a hashref of servers and their jobs, e.g.:

=begin text

    {
        'localhost:4730' => {
            # Job ID
            'H:tundra.home:8' => {

                # Whether or not the job is currently running
                'running' => 1,

                # Numerator and denominator of the job's progress
                # (in this example, job is 1333/2000 complete)
                'numerator' => 1333,    # 0 if the job haven't been started yet
                'denominator' => 2000   # 1 if the job haven't been started yet;
                                        # 0 if the job has been cancelled
                
            },

            # ...

        },

        # ...
    }

=end text

Returns C<undef> on error.

=cut

requires 'show_jobs';

=head2 C<$self-E<gt>cancel_job($job_id)>

Remove a given job from all the configured servers' queues.

Parameters:

=over 4

=item * job ID (e.g. "H:localhost.localdomain:8")

=back

Returns true (1) if the job has been cancelled, false (C<undef>) on error.

=cut

requires 'cancel_job';

=head2 C<$self-E<gt>server_status()>

Get status from all the configured servers.

Returns a hashref of servers and their statuses, e.g.:

=begin text

    {
        'localhost:4730' => {
            # Function name
            'NinetyNineBottlesOfBeer' => {

                # Number of queued (waiting to be run) jobs
                'total' => 4,

                # Number of currently running jobs
                'running' => 1,

                # Number of currently registered workers
                'available_workers' => 1
                
            },

            # ...
        },

        # ...

    };

=end text

Returns C<undef> on error.

=cut

requires 'server_status';

=head2 C<$self-E<gt>workers()>

Get a list of workers from all the configured servers.

Returns a hashref of servers and their workers, e.g.:

=begin text

    {
        'localhost:4730' => [
            {
                # Unique integer file descriptor of the worker
                'file_descriptor' => 23,
                
                # IP address of the worker
                'ip_address' => '127.0.0.1',

                # Client ID of the worker (might be undefined if the ID is '-')
                'client_id' => undef,

                # List of functions the worker covers
                'functions' => [
                    'NinetyNineBottlesOfBeer',
                    'Addition'
                ]
            },
            # ...
        ],

        # ...

    };

=end text

Returns C<undef> on error.

=cut

requires 'workers';

no Moose;    # gets rid of scaffolding

1;
