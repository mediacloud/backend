#!/usr/bin/env perl
#
# Snapshot various topic queries to CSV and build a GEXF file
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Job::StatefulBroker;
use MediaWords::Job::Lock;
use MediaWords::Job::State;
use MediaWords::Job::State::ExtraTable;
use MediaWords::Job::StatefulBroker;
use MediaWords::TM::Snapshot;


sub run_job($)
{
    my $args = shift;

    my $db = MediaWords::DB::connect_to_db();

    my $topics_id  = $args->{ topics_id };
    my $note       = $args->{ note };
    my $snapshots_id = $args->{ snapshots_id };

    my $state_updater = $args->{ state_updater };

    die( "'topics_id' is undefined" ) unless ( defined $topics_id );

    unless ( $state_updater ) {
        die "State updater is not set.";
    }

    # No transaction started because apparently snapshot_topic() does start one itself
    $snapshots_id = MediaWords::TM::Snapshot::snapshot_topic(
        $db, $topics_id, $snapshots_id, $note, $state_updater
    );

    INFO "Adding a new word2vec model generation job for snapshot $snapshots_id...";
    MediaWords::Job::Broker->new( 'MediaWords::Job::Word2vec::GenerateSnapshotModel' )->add_to_queue( { snapshots_id => $snapshots_id } );
}

sub main()
{
    my $app = MediaWords::Job::StatefulBroker->new( 'MediaWords::Job::TM::SnapshotTopic' );

    # Only run one job for each topic at a time
    my $lock = MediaWords::Job::Lock->new( 'MediaWords::Job::TM::SnapshotTopic', 'topics_id' );

    my $extra_table = MediaWords::Job::State::ExtraTable->new( 'snapshots', 'state', 'message' );
    my $state = MediaWords::Job::State->new( $extra_table );

    $app->start_worker( \&run_job, $lock, $state );
}

main();
