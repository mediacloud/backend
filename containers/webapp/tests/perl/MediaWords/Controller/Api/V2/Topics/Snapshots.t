use strict;
use warnings;
use utf8;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;
use Catalyst::Test 'MediaWords';
use Readonly;

use MediaWords::DB;
use MediaWords::Test::API;
use MediaWords::Test::Solr;
use MediaWords::Test::DB::Create;
use MediaWords::Controller::Api::V2::Topics;
use MediaWords::DBI::Auth::Roles;
use MediaWords::Test::API;

Readonly my $NUM_MEDIA            => 5;
Readonly my $NUM_FEEDS_PER_MEDIUM => 2;
Readonly my $NUM_STORIES_PER_FEED => 10;

sub test_generate_fetch_word2vec_model($)
{
    my $db = shift;

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, 'test_word2vec_model' );
    my $topics_id = $topic->{ topics_id };

    # Allow test user to "write" to this topic
    my $auth_user = $db->query(
        <<SQL,
        SELECT auth_users_id
        FROM auth_user_api_keys
        WHERE api_key = ?
SQL
        MediaWords::Test::API::get_test_api_key()
    )->hash;
    my $auth_users_id    = $auth_user->{ auth_users_id };
    my $topic_permission = $db->create(
        'topic_permissions',
        {
            auth_users_id => $auth_users_id,
            topics_id     => $topics_id,
            permission    => 'write'
        }
    );

    # Add all test stories to the test topic
    $db->query(
        <<SQL,
        INSERT INTO topic_stories (topics_id, stories_id)
        SELECT ?, stories_id FROM stories
SQL
        $topics_id
    );

    my $snapshots_id = $db->query(
        <<SQL,
        INSERT INTO snapshots (topics_id, snapshot_date, start_date, end_date)
        VALUES (?, NOW(), NOW(), NOW())
        RETURNING snapshots_id
SQL
        $topics_id
    )->flat->[ 0 ];

    $db->query(
        <<SQL,
        INSERT INTO snap.stories (snapshots_id, media_id, stories_id, url, guid, title, publish_date, collect_date)
        SELECT ?, media_id, stories_id, url, guid, title, publish_date, collect_date FROM stories
SQL
        $snapshots_id
    );

    # Test that no models exist for snapshot
    {
        # No snapshots/single/<snapshots_id> available at the moment
        my $fetched_snapshots = MediaWords::Test::API::test_get( "/api/v2/topics/$topics_id/snapshots/list" );

        my $found_snapshot = undef;
        for my $snapshot ( @{ $fetched_snapshots->{ snapshots } } )
        {
            if ( $snapshot->{ snapshots_id } == $snapshots_id )
            {
                $found_snapshot = $snapshot;
                last;
            }
        }

        ok( $found_snapshot );
        ok( $found_snapshot->{ word2vec_models } );
        is( ref $found_snapshot->{ word2vec_models }, ref( [] ) );
        is( scalar( @{ $found_snapshot->{ word2vec_models } } ), 0 );
    }

    # Add model generation job
    MediaWords::JobManager::Job::add_to_queue( 'MediaWords::Job::Word2vec::GenerateSnapshotModel', { snapshots_id => $snapshots_id } );

    # Wait for model to appear
    my $found_models_id = undef;
    for ( my $retry = 1 ; $retry <= 10 ; ++$retry )
    {
        INFO "Trying to fetch generated snapshot model for $retry time...";

        # No snapshots/single/<snapshots_id> available at the moment
        my $fetched_snapshots = MediaWords::Test::API::test_get( "/api/v2/topics/$topics_id/snapshots/list" );

        my $found_snapshot = undef;
        for my $snapshot ( @{ $fetched_snapshots->{ snapshots } } )
        {
            if ( $snapshot->{ snapshots_id } == $snapshots_id )
            {
                $found_snapshot = $snapshot;
                last;
            }
        }

        ok( $found_snapshot );
        if ( scalar( @{ $found_snapshot->{ word2vec_models } } ) > 0 )
        {
            $found_models_id = $found_snapshot->{ word2vec_models }->[ 0 ]->{ models_id };
            last;
        }

        INFO "Model not found, will retry shortly";
        sleep( 1 );
    }

    ok( defined $found_models_id, "Model's ID was not found after all of the retries" );

    # Try fetching the model
    my $path = "/api/v2/topics/$topics_id/snapshots/$snapshots_id/word2vec_model/$found_models_id?key=" .
      MediaWords::Test::API::get_test_api_key();
    my $response = request( $path );    # Catalyst::Test::request()
    ok( $response->is_success );

    my $model_data = $response->decoded_content;
    ok( defined $model_data );

    my $model_data_length = length( $model_data );
    INFO "Model data length: $model_data_length";
    ok( $model_data_length > 0 );
}

sub test_topics($)
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::DB::Create::create_test_story_stack_numerated( $db, $NUM_MEDIA, $NUM_FEEDS_PER_MEDIUM,
        $NUM_STORIES_PER_FEED );

    $media = MediaWords::Test::DB::Create::add_content_to_test_story_stack( $db, $media );

    MediaWords::Test::Solr::setup_test_index( $db );

    MediaWords::Test::API::setup_test_api_key( $db );

    test_generate_fetch_word2vec_model( $db );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_topics( $db );

    done_testing();
}

main();
