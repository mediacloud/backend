use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Readonly;
use Test::More;
use Test::Deep;

use MediaWords::Test::API;
use MediaWords::Test::DB;
use MediaWords::Test::DB::Create;
use MediaWords::Test::Solr;
use MediaWords::Test::Supervisor;

# test users/list and single
sub test_users_list($)
{
    my ( $db ) = @_;

    my $num_users = 8;

    my $expected_auth_users = [];
    for my $i ( 1 .. $num_users )
    {
        my $auth_user = {
            email             => "foo_$i\@foo.bar",
            full_name         => "foo bar $1",
            notes             => "notes $1",
            password_hash     => 'password hash',
            max_topic_stories => $i
        };
        $auth_user = $db->create( 'auth_users', $auth_user );
        push( @{ $expected_auth_users }, $auth_user );
    }

    my $label = "users/list";

    my $r = test_get( '/api/v2/users/list', {} );

    my $fields = [ qw ( email full_name notes created_date max_topic_stories ) ];
    rows_match( $label, $r->{ users }, $expected_auth_users, "auth_users_id", $fields );

    $label = "users/single";

    my $expected_single = $expected_auth_users->[ 0 ];

    $r = test_get( '/api/v2/users/single/' . $expected_single->{ auth_users_id }, {} );
    rows_match( $label, $r->{ users }, [ $expected_single ], 'feeds_id', $fields );
}

sub test_users($)
{
    my ( $db ) = @_;

    test_users_list( $db );
}

# sub test_feeds($)
# {
#     my ( $db ) = @_;

#     my $media = MediaWords::Test::DB::Create::create_test_story_stack_numerated( $db, $NUM_MEDIA, $NUM_FEEDS_PER_MEDIUM,
#         $NUM_STORIES_PER_FEED );

#     $media = MediaWords::Test::DB::Create::add_content_to_test_story_stack( $db, $media );

#     # MediaWords::Test::Solr::setup_test_index( $db );

#     MediaWords::Test::API::setup_test_api_key( $db );

#     # test for required fields errors
#     test_post( '/api/v2/feeds/create', {}, 1 );
#     test_put( '/api/v2/feeds/update', { name => 'foo' }, 1 );

#     my $medium = $db->query( "select * from media limit 1" )->hash;

#     # simple tag creation
#     my $create_input = {
#         media_id => $medium->{ media_id },
#         name     => 'feed name',
#         url      => 'http://feed.create',
#         type     => 'syndicated',
#         active   => 't',
#     };

#     my $r = test_post( '/api/v2/feeds/create', $create_input );
#     validate_db_row( $db, 'feeds', $r->{ feed }, $create_input, 'create feed' );

#     # error on update non-existent tag
#     test_put( '/api/v2/feeds/update', { feeds_id => -1 }, 1 );

#     # simple update
#     my $update_input = {
#         feeds_id => $r->{ feed }->{ feeds_id },
#         name     => 'feed name update',
#         url      => 'http://feed.create/update',
#         type     => 'web_page',
#         active   => 'f',
#     };

#     $r = test_put( '/api/v2/feeds/update', $update_input );
#     validate_db_row( $db, 'feeds', $r->{ feed }, $update_input, 'update feed' );

#     $r = test_post( '/api/v2/feeds/scrape', { media_id => $medium->{ media_id } } );
#     ok( $r->{ job_state }, "feeds/scrape job state returned" );
#     is( $r->{ job_state }->{ media_id }, $medium->{ media_id }, "feeds/scrape media_id" );
#     ok( $r->{ job_state }->{ state } ne 'error', "feeds/scrape job state is not an error" );

#     $r = test_get( '/api/v2/feeds/scrape_status', { media_id => $medium->{ media_id } } );
#     is( $r->{ job_states }->[ 0 ]->{ media_id }, $medium->{ media_id }, "feeds/scrape_status media_id" );

#     $r = test_get( '/api/v2/feeds/scrape_status', {} );
#     is( $r->{ job_states }->[ 0 ]->{ media_id }, $medium->{ media_id }, "feeds/scrape_status all media_id" );

#     test_feeds_list( $db );
# }

sub main
{
    MediaWords::Test::DB::test_on_test_database( \&test_users );

    done_testing();
}

main();
