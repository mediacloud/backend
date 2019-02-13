package MediaWords::JobManager::Broker;

#
# Abstract job broker
#

use strict;
use warnings;
use Modern::Perl "2015";

use Moose::Role;

=head2 C<$self-E<gt>start_worker($function_name)>

Start a worker.

Should call C<$function_name::run( $args )> to do the actual
work. C<$job> is job handle or identifier used by helpers.

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

no Moose;    # gets rid of scaffolding

1;
