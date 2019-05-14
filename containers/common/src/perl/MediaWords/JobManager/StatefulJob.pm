package MediaWords::JobManager::StatefulJob;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose::Role;
with 'MediaWords::JobManager::AbstractJob';

use MediaWords::JobManager::AbstractStatefulJob;
use MediaWords::JobManager::Job;


# override add_to_queue method to add state actions, including add a new job_states row with a state
# of $STATE_QUEUED. optinoally include a $db handle to use to create the job_states row
sub add_to_queue($;$$)
{
    my ( $function_name, $args, $priority ) = @_;

    my $db = MediaWords::DB::connect_to_db();
    $args //= {};

    my $job_state = MediaWords::JobManager::AbstractStatefulJob::_create_queued_job_state( $db, $function_name, $args, $priority );
    $args->{ job_states_id } = $job_state->{ job_states_id };

    # FIXME it's not clear to me what is it updating here right after adding a
    # job, and the worker class is not visible from this package, so commenting
    # it out.
    #
    # eval { MediaWords::JobManager::AbstractStatefulJob::_update_table_state( $db, $function_name, $job_state ); };
    # LOGCONFESS( "error updating table state: $@" ) if ( $@ );

    MediaWords::JobManager::Job::add_to_queue( $function_name, $args, $priority );
}

no Moose;    # gets rid of scaffolding

1;
