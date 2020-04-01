package MediaWords::TM::Worker;

#
# Run through stories found for the given topic and find all the links in
# each story.
#
# For each link, try to find whether it matches any given story. If it doesn't,
# create a new story. Add that story's links to the queue if it matches the
# pattern for the topic. Write the resulting stories and links to
# topic_stories and topic_links.
#
# Options:
#
# * dedup_stories - run story deduping code over existing topic stories;
#   only necessary to rerun new dedup code
#
# * import_only - only run import_seed_urls and import_solr_seed and return
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Job::Lock;
use MediaWords::Job::State;
use MediaWords::Job::State::ExtraTable;
use MediaWords::Job::StatefulBroker;
use MediaWords::TM::Mine;


sub _run_job($)
{
    my $args = shift;

    my $db = MediaWords::DB::connect_to_db();

    my $topics_id                       = $args->{ topics_id };
    my $import_only                     = $args->{ import_only } // 0;
    my $cache_broken_downloads          = $args->{ cache_broken_downloads } // 0;
    my $skip_outgoing_foreign_rss_links = $args->{ skip_outgoing_foreign_rss_links } // 0;
    my $skip_post_processing            = $args->{ skip_post_processing } // 0;
    my $test_mode                       = $args->{ test_mode } // 0;
    my $snapshots_id                    = $args->{ snapshots_id } // undef;

    my $state_updater                   = $args->{ state_updater };

    unless ( $topics_id )
    {
        die "'topics_id' is not set.";
    }

    unless ( $state_updater ) {
        die "State updater is not set.";
    }

    my $topic = $db->find_by_id( 'topics', $topics_id )
      or die( "Unable to find topic '$topics_id'" );

    my $options = {
        import_only                     => $import_only,
        cache_broken_downloads          => $cache_broken_downloads,
        skip_outgoing_foreign_rss_links => $skip_outgoing_foreign_rss_links,
        skip_post_processing            => $skip_post_processing,
        test_mode                       => $test_mode,
        snapshots_id                    => $snapshots_id
    };

    MediaWords::TM::Mine::mine_topic( $db, $topic, $options, $state_updater );
}

sub start_topics_mine_worker($)
{
    my $queue_name = shift;

    my $app = MediaWords::Job::StatefulBroker->new( $queue_name );

    my $lock = MediaWords::Job::Lock->new(

        # Define this here so that ::MineTopicPublic operates on the same lock
        'MediaWords::Job::TM::MineTopic',

        # Only run one job for each topic at a time
        'topics_id',

    );

    my $extra_table = MediaWords::Job::State::ExtraTable->new( 'topics', 'state', 'message' );
    my $state = MediaWords::Job::State->new( $extra_table );
    $app->start_worker( \&_run_job, $lock, $state );
}

1;
