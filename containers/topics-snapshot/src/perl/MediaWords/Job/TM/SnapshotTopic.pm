package MediaWords::Job::TM::SnapshotTopic;

#
# Snapshot various topic queries to csv and build a gexf file
#

use strict;
use warnings;

use Moose;
with 'MediaWords::JobManager::AbstractStatefulJob';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::TM::Snapshot;

# only run one job for each topic at a time
sub get_run_lock_arg
{
    return 'topics_id';
}

sub get_run_lock_type
{
    return 'MediaWords::Job::TM::SnapshotTopic';
}

sub get_state_table_info
{
    return { table => 'snapshots', state => 'state', message => 'message' };
}

# Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    my $db = MediaWords::DB::connect_to_db();

    my $topics_id  = $args->{ topics_id };
    my $note       = $args->{ note };
    my $bot_policy = $args->{ bot_policy };
    my $periods    = $args->{ periods };
    my $snapshots_id = $args->{ snapshots_id };

    die( "'topics_id' is undefined" ) unless ( defined $topics_id );

    # No transaction started because apparently snapshot_topic() does start one itself
    $snapshots_id = MediaWords::TM::Snapshot::snapshot_topic( 
        $db, $topics_id, $snapshots_id, $note, $bot_policy, $periods
    );

    INFO "Adding a new word2vec model generation job for snapshot $snapshots_id...";
    MediaWords::JobManager::Job::add_to_queue( 'MediaWords::Job::Word2vec::GenerateSnapshotModel', { snapshots_id => $snapshots_id } );
}

no Moose;    # gets rid of scaffolding

1;
