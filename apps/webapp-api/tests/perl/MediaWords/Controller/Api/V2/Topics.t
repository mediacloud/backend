use strict;
use warnings;
use utf8;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::Deep;
use Test::More;
use Catalyst::Test 'MediaWords';
use Readonly;

use MediaWords::DB;
use MediaWords::Controller::Api::V2::Topics;
use MediaWords::DBI::Auth::Roles;
use MediaWords::Test::API;
use MediaWords::Test::Rows;
use MediaWords::Test::DB::Create;
use MediaWords::Test::DB::Create::User;

Readonly my $NUM_MEDIA            => 5;
Readonly my $NUM_FEEDS_PER_MEDIUM => 2;
Readonly my $NUM_STORIES_PER_FEED => 10;

sub test_validate_max_stories($)
{
    my ( $db ) = @_;

    my $label = "test_validate_max_stories";

    my $auth_user_api_key = MediaWords::Test::DB::Create::User::create_test_user( $db, $label );
    my $auth_user = $db->query(
        <<SQL,
        SELECT auth_users_id
        FROM auth_user_api_keys
        WHERE api_key = ?
SQL
        $auth_user_api_key
    )->hash;
    my $auth_users_id = $auth_user->{ auth_users_id };

    $db->query( "DELETE FROM auth_users_roles_map" );

    eval {
        MediaWords::Controller::Api::V2::Topics::_validate_max_stories(
            $db,
            1,
            $auth_users_id,
        )
    };
    ok( !$@, "$label max stories less than user setting: validated $@" );

    eval {
        MediaWords::Controller::Api::V2::Topics::_validate_max_stories(
            $db,
            1000000,
            $auth_users_id,
        )
    };
    ok( $@, "$label max stories more than user setting: died" );

    $db->query( <<SQL,
        INSERT INTO auth_users_roles_map (
            auth_users_id,
            auth_roles_id
        )
            SELECT
                ? AS auth_users_id,
                auth_roles_id
            FROM auth_roles
            WHERE role = ?
SQL
        $auth_users_id, $MediaWords::DBI::Auth::Roles::List::ADMIN
    );

    eval {
        MediaWords::Controller::Api::V2::Topics::_validate_max_stories(
            $db,
            1000000,
            $auth_users_id,
        )
    };
    ok( !$@, "$label admin user: validate $@" );

    $db->query( "delete from auth_users_roles_map" );
    $db->query( <<SQL,
        INSERT INTO auth_users_roles_map (
            auth_users_id, auth_roles_id
        )
            SELECT
                ? AS auth_users_id,
                auth_roles_id
            FROM auth_roles
            WHERE role = ?
SQL
        $auth_users_id, $MediaWords::DBI::Auth::Roles::List::ADMIN_READONLY
    );

    eval {
        MediaWords::Controller::Api::V2::Topics::_validate_max_stories(
            $db,
            1000000,
            $auth_users_id,
        )
    };
    ok( !$@, "$label admin read user: validate $@" );
}

sub test_is_mc_queue_user($)
{
    my ( $db ) = @_;

    my $label = "test_is_mc_queue_user";

    my $auth_user_api_key = MediaWords::Test::DB::Create::User::create_test_user( $db, $label );
    my $auth_user = $db->query( <<SQL,
        SELECT auth_users_id
        FROM auth_user_api_keys
        WHERE api_key = ?
SQL
        $auth_user_api_key
    )->hash;
    my $auth_users_id = $auth_user->{ auth_users_id };

    $db->query( "DELETE FROM auth_users_roles_map WHERE auth_users_id = ?", $auth_users_id );

    my $got = MediaWords::Controller::Api::V2::Topics::_is_mc_queue_user( $db, $auth_users_id );
    ok( !$got, "$label default user should be public" );

    for my $role ( @{ MediaWords::DBI::Auth::Roles::List::topic_mc_queue_roles() } )
    {
        $db->query( "delete from auth_users_roles_map where auth_users_id = ?", $auth_users_id );
        $db->query( <<SQL,
            INSERT INTO auth_users_roles_map (
                auth_users_id,
                auth_roles_id
            )
                SELECT
                    ? AS auth_users_id,
                    auth_roles_id
                FROM auth_roles
                WHERE role = ?
SQL
            $auth_users_id, $MediaWords::DBI::Auth::Roles::List::ADMIN
        );

        my $got = MediaWords::Controller::Api::V2::Topics::_is_mc_queue_user( $db, $auth_users_id );
        ok( $got, "$label user with role '$role' should be mc" );
    }
}

sub test_update_query_scope($)
{
    my ( $db ) = @_;

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, 'query scope' );

    # for each call, just test whether or not an error is generated

    # query change should not trigger error if there are no spidered topic stories yet
    MediaWords::Test::API::test_put(
        "/api/v2/topics/$topic->{ topics_id }/update",
        {
            start_date => '2010-01-01',
        }
    );

    # insert some spidered stories so that we can check for the date and media conditions
    my $story_stack = MediaWords::Test::DB::Create::create_test_story_stack_numerated(
        $db,
        1,
        1,
        1,
        'query_scope',
    );
    $db->query( <<SQL,
        INSERT INTO topic_stories (
            topics_id,
            stories_id,
            iteration
        )
            SELECT
                \$1 AS topics_id,
                stories_id,
                2 AS iteration
            FROM stories
            WHERE media_id = \$2
SQL
        $topic->{ topics_id }, $story_stack->{ media_query_scope_0 }->{ media_id }
    );

    MediaWords::Test::API::test_put(
        "/api/v2/topics/$topic->{ topics_id }/update",
        {
            description => 'new query scope description',
        }
    );
    MediaWords::Test::API::test_put(
        "/api/v2/topics/$topic->{ topics_id }/update",
        {
            end_date => $topic->{ end_date },
        }
    );

    {
        my $update_start_date = MediaWords::Util::SQL::increment_day( $topic->{ start_date }, 1 );
        MediaWords::Test::API::test_put(
            "/api/v2/topics/$topic->{ topics_id }/update",
            {
                start_date => $update_start_date,
            },
            1,
        );
    }

    MediaWords::Test::API::test_put(
        "/api/v2/topics/$topic->{ topics_id }/update",
        {
            end_date => $topic->{ end_date },
        }
    );

    {
        my $update_end_date = MediaWords::Util::SQL::increment_day( $topic->{ end_date }, -1 );
        MediaWords::Test::API::test_put(
            "/api/v2/topics/$topic->{ topics_id }/update",
            {
                end_date => $update_end_date,
            },
            1,
        );
    }

    {
        my $medium_a = MediaWords::Test::DB::Create::create_test_medium( $db, 'query scope a' );
        my $medium_b = MediaWords::Test::DB::Create::create_test_medium( $db, 'query scope b' );
        my $media_ids = [ map { $_->{ media_id } } ( $medium_a, $medium_b ) ];

        MediaWords::Test::API::test_put(
            "/api/v2/topics/$topic->{ topics_id }/update",
            {
                media_ids => $media_ids,
            }
        );

        MediaWords::Test::API::test_put(
            "/api/v2/topics/$topic->{ topics_id }/update",
            {
                media_ids => [],
            },
            1,
        );
        MediaWords::Test::API::test_put(
            "/api/v2/topics/$topic->{ topics_id }/update",
            {
                media_ids => [ $medium_a->{ media_id } ],
            },
            1,
        );
    }

    {
        my $tag_a = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'query_scope:tag_a' );
        my $tag_b = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'query_scope:tag_b' );
        my $tags_ids = [ map { $_->{ tags_id } } ( $tag_a, $tag_b ) ];

        MediaWords::Test::API::test_put(
            "/api/v2/topics/$topic->{ topics_id }/update",
            {
                media_tags_ids => $tags_ids,
            }
        );

        MediaWords::Test::API::test_put(
            "/api/v2/topics/$topic->{ topics_id }/update",
            {
                media_tags_ids => [],
            },
            1,
        );
        MediaWords::Test::API::test_put(
            "/api/v2/topics/$topic->{ topics_id }/update",
            {
                media_tags_ids => [ $tag_a->{ tags_id } ],
            },
            1,
        );
    }
}

# return number of topic_stories for the topic for which link_mined is false
sub get_respider_count($$)
{
    my ( $db, $topic ) = @_;

    my ( $count ) = $db->query( <<SQL,
        SELECT COUNT(*)
        FROM topic_stories
        WHERE
            topics_id = ? AND
            link_mined = 'f'
SQL
        $topic->{ topics_id }
    )->flat();

    return $count;
}

sub test_set_stories_respidering($)
{
    my ( $db ) = @_;

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, 'respider' );

    my $num_stories = 10;

    my $media = MediaWords::Test::DB::Create::create_test_story_stack_numerated(
        $db,
        1,
        1,
        $num_stories,
        'respider'
    );

    my $medium = $media->{ media_respider_0 };

    $db->query( <<SQL,
        INSERT INTO topics_media_map (topics_id, media_id)
        VALUES (\$1, \$2)
SQL
        $topic->{ topics_id }, $medium->{ media_id }
    );

    $db->query( <<SQL,
        INSERT INTO topic_stories (
            topics_id,
            stories_id,
            link_mined
        )
            SELECT
                t.topics_id,
                s.stories_id,
                't' AS link_mined
            FROM
                topics AS t,
                stories AS s
            WHERE
                t.topics_id = \$1 AND
                s.media_id = \$2
SQL
        $topic->{ topics_id }, $medium->{ media_id }
    );

    my $topic_stories = $db->query( <<SQL,
        SELECT *
        FROM topic_stories
        WHERE topics_id = ?
SQL
        $topic->{ topics_id }
    )->hashes;

    is( scalar( @{ $topic_stories } ), $num_stories );

    MediaWords::Controller::Api::V2::Topics::_set_stories_respidering(
        $db,
        $topic,
        {
            name => 'new respider name',
        }
    );
    $topic = $db->find_by_id( 'topics', $topic->{ topics_id } );
    ok( !$topic->{ respider_stories }, "respider_stories not set after no scope pdate" );

    MediaWords::Controller::Api::V2::Topics::_set_stories_respidering(
        $db,
        $topic,
        {
            solr_seed_query => 'new respider name',
        }
    );
    $topic = $db->find_by_id( 'topics', $topic->{ topics_id } );
    ok( $topic->{ respider_stories }, "respider_stories set after query update" );

    $db->query( <<SQL,
        UPDATE topic_stories SET
            link_mined = 't'
        WHERE topics_id = ?
SQL
        $topic->{ topics_id }
    );

    my $start_date = '2017-01-01';
    my $end_date   = '2017-02-01';
    $topic = $db->update_by_id(
        'topics',
        $topic->{ topics_id },
        { respider_stories => 'f', start_date => $start_date, end_date => $end_date }
    );

    $db->query( <<SQL,
        UPDATE stories SET
            publish_date = \$1
        WHERE media_id = \$2
SQL
        $start_date, $medium->{ media_id }
    );

    $db->query( <<SQL,
        UPDATE stories SET
            publish_date = '2016-01-01'
        WHERE stories_id IN (
            SELECT stories_id
            FROM stories
            WHERE media_id = ?
            ORDER BY stories_id
            LIMIT 1
        )
SQL
        $medium->{ media_id }
    );

    $db->query( <<SQL,
        UPDATE stories SET
            publish_date = '2018-01-01'
        WHERE stories_id IN (
            SELECT stories_id
            FROM stories
            WHERE media_id = ?
            ORDER BY stories_id DESC
            LIMIT 1
        )
SQL
        $medium->{ media_id }
    );

    my $old_start_date = $topic->{ start_date };
    my $old_end_date   = $topic->{ end_date };
    my $new_start_date = '2016-01-01';
    my $new_end_date   = '2018-01-01';

    MediaWords::Controller::Api::V2::Topics::_set_stories_respidering(
        $db,
        $topic,
        {
            start_date => $new_start_date,
            end_date => $new_end_date,
        }
    );

    $topic = $db->find_by_id( 'topics', $topic->{ topics_id } );
    ok( $topic->{ respider_stories }, "respider_stories set after date update" );
    is( $topic->{ respider_start_date }, $old_start_date, "respider_start_date set" );
    is( $topic->{ respider_end_date },   $old_end_date,   "respider_end_date set" );
}

sub test_topics_reset
{
    my ( $db ) = @_;

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, 'reset' );
    my $topics_id = $topic->{ topics_id };

    my $num_stories = 10;
    my $story_stack = MediaWords::Test::DB::Create::create_test_story_stack_numerated(
        $db,
        1,
        1,
        $num_stories,
        'reset'
    );

    $db->query( "UPDATE TOPICS SET solr_seed_query_run = 't' WHERE topics_id = ?", $topics_id );

    $db->query( <<SQL,
        INSERT INTO topic_stories (
            topics_id,
            stories_id,
            iteration
        )
            SELECT
                \$1 AS topics_id,
                stories_id,
                2 AS iteration
            FROM stories
            WHERE media_id = \$2
SQL
        $topics_id, $story_stack->{ media_reset_0 }->{ media_id }
    );

    my ( $stories_count ) = $db->query( <<SQL,
        SELECT COUNT(*)
        FROM topic_stories
        WHERE topics_id = ?
SQL
        $topics_id
    )->flat();
    is( $stories_count, $num_stories, "topics reset: stories before reset" );

    $db->query( <<SQL,
        INSERT INTO topic_links (
            topics_id,
            stories_id,
            url
        )
            SELECT
                ts.topics_id,
                ts.stories_id,
                'http://foo.bar' AS url
            FROM topic_stories
            WHERE topics_id = \$1
SQL
        $topics_id
    );

    my ( $links_count ) = $db->query( <<SQL,
        SELECT COUNT(*)
        FROM topic_links
        WHERE topics_id = ?
SQL
        $topics_id
    )->flat();
    is( $links_count, $num_stories, "topics reset: links before reset" );

    $db->query( <<SQL,
        INSERT INTO topic_seed_urls (
            topics_id,
            stories_id
        )
            SELECT
                topics_id,
                stories_id
            FROM topic_stories
            WHERE topics_id = ?
SQL
        $topics_id
    );

    my ( $seeds_count ) = $db->query( <<SQL,
        SELECT COUNT(*)
        FROM topic_seed_urls
        WHERE topics_id = ?
SQL
        $topics_id
    )->flat();
    is( $seeds_count, $num_stories, "topics reset: seed urls before reset" );

    $db->update_by_id( 'topics', $topic->{ topics_id }, { state => 'running' } );

    # this should generate an erro since the topic is running
    MediaWords::Test::API::test_put( "/api/v2/topics/$topic->{ topics_id }/reset", {}, 1 );

    $db->update_by_id(
        'topics',
        $topic->{ topics_id },
        {
            state => 'error',
            message => 'test message',
        }
    );

    MediaWords::Test::API::test_put( "/api/v2/topics/$topic->{ topics_id }/reset", {} );

    my ( $got_stories_count ) = $db->query( <<SQL,
        SELECT COUNT(*)
        FROM topic_stories
        WHERE topics_id = ?
SQL
        $topics_id
    )->flat;
    is( $got_stories_count, 0, "topics reset: stories after reset" );

    my ( $got_links_count ) = $db->query( <<SQL,
        SELECT COUNT(*)
        FROM topic_links
        WHERE topics_id = ?
SQL
        $topics_id
    )->flat;
    is( $got_links_count, 0, "topics reset: links after reset" );

    my ( $got_seed_count ) = $db->query( <<SQL,
        SELECT COUNT(*)
        FROM topic_seed_urls
        WHERE topics_id = ?
SQL
        $topics_id
    )->flat;
    is( $got_seed_count, 0, "topics reset: seed urls after reset" );

    my $reset_topic = $db->find_by_id( 'topics', $topics_id );

    ok( !$reset_topic->{ solr_seed_query_run }, "topics reset: solr_seed_query_run false after reset" );
    is( $topic->{ state }, 'created but not queued', "topics_reset: state after rest" );
    ok( !$topic->{ message }, "topics_reset: null message" );
}

sub test_seed_queries
{
    my ( $db ) = @_;

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, 'seed' );
    my $topics_id = $topic->{ topics_id };

    my $tsq_input = {
        topics_id => $topics_id,
        platform  => 'twitter',
        source    => 'crimson_hexagon',
        query     => 'foo'
    };
    MediaWords::Test::API::test_put( "/api/v2/topics/$topics_id/add_seed_query", $tsq_input );

    my $got_tsq = $db->query( <<SQL,
        SELECT *
        FROM topic_seed_queries
        WHERE topics_id = ?
SQL
        $topics_id
    )->hash();

    for my $field ( keys( %{ $tsq_input } ) )
    {
        is( $got_tsq->{ $field }, $tsq_input->{ $field }, "seed query $field value" );
    }

    MediaWords::Test::API::test_put( "/api/v2/topics/$topics_id/remove_seed_query",
        { topic_seed_queries_id => $got_tsq->{ topic_seed_queries_id } } );

    my ( $tsq_count ) = $db->query( <<SQL,
        SELECT COUNT(*)
        FROM topic_seed_queries
        WHERE topics_id = ?
SQL
        $topics_id
    )->flat;
    is( $tsq_count, 0, "seed query count after remove" );
}

sub test_topics
{
    my ( $db ) = @_;

    MediaWords::Test::API::setup_test_api_key( $db );

    test_seed_queries( $db );
    test_update_query_scope( $db );
    test_set_stories_respidering( $db );
    test_topics_reset( $db );
    test_validate_max_stories( $db );
    test_is_mc_queue_user( $db );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_topics( $db );

    done_testing();
}

main();
