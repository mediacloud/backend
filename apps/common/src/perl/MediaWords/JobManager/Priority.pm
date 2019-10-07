package MediaWords::JobManager::Priority;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;


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

sub priority_is_valid($)
{
    my $priority = shift;
    return exists $valid_priorities{ $priority };
}

1;
