#!/usr/bin/env perl

use strict;
use warnings;

use Catalyst::Test 'MediaWords';

use MediaWords::CommonLibs;
use Modern::Perl "2015";

use Readonly;
use Test::More;
use URI::Escape;

use MediaWords::Test::API;
use MediaWords::Test::DB;

# public and admin_read key users
my $_public_user;

# test topics
my $_public_topic;
my $_topic_a;
my $_topic_b;

# this hash maps each api end point to the kind of permission it should have: public, admin_read, or topics
my $_url_permission_types = {
    '/api/v2/auth/activate'                       => 'admin',
    '/api/v2/auth/change_password'                => 'public',
    '/api/v2/auth/login'                          => 'admin_read',
    '/api/v2/auth/profile'                        => 'public',
    '/api/v2/auth/register'                       => 'admin',
    '/api/v2/auth/reset_password'                 => 'admin',
    '/api/v2/auth/resend_activation_link'         => 'admin',
    '/api/v2/auth/reset_api_key'                  => 'public',
    '/api/v2/auth/send_password_reset_link'       => 'admin',
    '/api/v2/controversies/list'                  => 'public',
    '/api/v2/controversies/single'                => 'public',
    '/api/v2/controversy_dump_time_slices/list'   => 'public',
    '/api/v2/controversy_dump_time_slices/single' => 'public',
    '/api/v2/controversy_dumps/list'              => 'public',
    '/api/v2/controversy_dumps/single'            => 'public',
    '/api/v2/downloads/list'                      => 'admin_read',
    '/api/v2/downloads/single'                    => 'admin_read',
    '/api/v2/feeds/create'                        => 'media_edit',
    '/api/v2/feeds/list'                          => 'public',
    '/api/v2/feeds/scrape'                        => 'media_edit',
    '/api/v2/feeds/scrape_status'                 => 'media_edit',
    '/api/v2/feeds/single'                        => 'public',
    '/api/v2/feeds/update'                        => 'media_edit',
    '/api/v2/mc_rest_simpleobject/list'           => 'public',
    '/api/v2/mc_rest_simpleobject/single'         => 'public',
    '/api/v2/media/create'                        => 'media_edit',
    '/api/v2/media/list'                          => 'public',
    '/api/v2/media/list_suggestions'              => 'media_edit',
    '/api/v2/media/mark_suggestion'               => 'media_edit',
    '/api/v2/media/put_tags'                      => 'media_edit',
    '/api/v2/media/single'                        => 'public',
    '/api/v2/media/submit_suggestion'             => 'public',
    '/api/v2/media/update'                        => 'media_edit',
    '/api/v2/mediahealth/list'                    => 'public',
    '/api/v2/mediahealth/single'                  => 'public',
    '/api/v2/sentences/count'                     => 'public',
    '/api/v2/sentences/field_count'               => 'public',
    '/api/v2/sentences/list'                      => 'admin_read',
    '/api/v2/sentences/single'                    => 'admin_read',
    '/api/v2/stats/list'                          => 'public',
    '/api/v2/stories/cliff'                       => 'admin_read',
    '/api/v2/stories/count'                       => 'public',
    '/api/v2/stories/field_count'                 => 'public',
    '/api/v2/stories/list'                        => 'admin_read',
    '/api/v2/stories/nytlabels'                   => 'admin_read',
    '/api/v2/stories/put_tags'                    => 'stories_edit',
    '/api/v2/stories/single'                      => 'admin_read',
    '/api/v2/stories/update'                      => 'stories_edit',
    '/api/v2/stories/word_matrix'                 => 'public',
    '/api/v2/stories_public/count'                => 'public',
    '/api/v2/stories_public/field_count'          => 'public',
    '/api/v2/stories_public/list'                 => 'public',
    '/api/v2/stories_public/single'               => 'public',
    '/api/v2/stories_public/word_matrix'          => 'public',
    '/api/v2/storiesbase/count'                   => 'public',
    '/api/v2/storiesbase/field_count'             => 'public',
    '/api/v2/storiesbase/list'                    => 'public',
    '/api/v2/storiesbase/single'                  => 'public',
    '/api/v2/storiesbase/word_matrix'             => 'public',
    '/api/v2/tag_sets/create'                     => 'admin',
    '/api/v2/tag_sets/list'                       => 'public',
    '/api/v2/tag_sets/single'                     => 'public',
    '/api/v2/tag_sets/update'                     => 'admin',
    '/api/v2/tags/create'                         => 'media_edit',
    '/api/v2/tags/list'                           => 'public',
    '/api/v2/tags/single'                         => 'public',
    '/api/v2/tags/update'                         => 'media_edit',
    '/api/v2/topics/create'                       => 'public',
    '/api/v2/topics/focal_set_definitions/create' => 'topics_write',
    '/api/v2/topics/focal_set_definitions/delete' => 'topics_write',
    '/api/v2/topics/focal_set_definitions/list'   => 'topics_read',
    '/api/v2/topics/focal_set_definitions/update' => 'topics_write',
    '/api/v2/topics/focal_sets/list'              => 'topics_read',
    '/api/v2/topics/foci/list'                    => 'topics_read',
    '/api/v2/topics/focus_definitions/create'     => 'topics_write',
    '/api/v2/topics/focus_definitions/delete'     => 'topics_write',
    '/api/v2/topics/focus_definitions/list'       => 'topics_read',
    '/api/v2/topics/focus_definitions/update'     => 'topics_write',
    '/api/v2/topics/list'                         => 'public',
    '/api/v2/topics/media/list'                   => 'topics_read',
    '/api/v2/topics/media/map'                    => 'topics_read',
    '/api/v2/topics/permissions/list'             => 'topics_admin',
    '/api/v2/topics/permissions/update'           => 'topics_admin',
    '/api/v2/topics/permissions/user_list'        => 'public',
    '/api/v2/topics/reset'                        => 'topics_admin',
    '/api/v2/topics/sentences/count'              => 'topics_read',
    '/api/v2/topics/single'                       => 'public',
    '/api/v2/topics/snapshots/generate'           => 'topics_write',
    '/api/v2/topics/snapshots/generate_status'    => 'topics_read',
    '/api/v2/topics/snapshots/list'               => 'topics_read',
    '/api/v2/topics/snapshots/word2vec_model'     => 'topics_read',
    '/api/v2/topics/spider'                       => 'topics_write',
    '/api/v2/topics/spider_status'                => 'public',
    '/api/v2/topics/stories/count'                => 'topics_read',
    '/api/v2/topics/stories/facebook'             => 'topics_read',
    '/api/v2/topics/stories/list'                 => 'topics_read',
    '/api/v2/topics/timespans/list'               => 'topics_read',
    '/api/v2/topics/update'                       => 'topics_write',
    '/api/v2/topics/wc/list'                      => 'topics_read',
    '/api/v2/util/is_syndicated_ap'               => 'public',
    '/api/v2/wc/list'                             => 'public',
};

# list of transformations needed to insert ids at proper places to make valid urls.  possible transformations:
# * ~topics_id~ - replace with a topic id
# * ~dummy_id~ - replace with a dummy int
my $_url_transformations = {
    '/api/v2/topics/focal_set_definitions/create' => '/api/v2/topics/~topics_id~/focal_set_definitions/create',
    '/api/v2/topics/focal_set_definitions/delete' => '/api/v2/topics/~topics_id~/focal_set_definitions/~dummy_id~/delete',
    '/api/v2/topics/focal_set_definitions/list'   => '/api/v2/topics/~topics_id~/focal_set_definitions/list',
    '/api/v2/topics/focal_set_definitions/update' => '/api/v2/topics/~topics_id~/focal_set_definitions/~dummy_id~/update',
    '/api/v2/topics/focal_sets/list'              => '/api/v2/topics/~topics_id~/focal_sets/list',
    '/api/v2/topics/foci/list'                    => '/api/v2/topics/~topics_id~/foci/list',
    '/api/v2/topics/focus_definitions/create'     => '/api/v2/topics/~topics_id~/focus_definitions/create',
    '/api/v2/topics/focus_definitions/delete'     => '/api/v2/topics/~topics_id~/focus_definitions/~dummy_id~/delete',
    '/api/v2/topics/focus_definitions/list'       => '/api/v2/topics/~topics_id~/focus_definitions/list',
    '/api/v2/topics/focus_definitions/update'     => '/api/v2/topics/~topics_id~/focus_definitions/~dummy_id~/update',
    '/api/v2/topics/media/list'                   => '/api/v2/topics/~topics_id~/media/list',
    '/api/v2/topics/media/map'                    => '/api/v2/topics/~topics_id~/media/map',
    '/api/v2/topics/permissions/list'             => '/api/v2/topics/~topics_id~/permissions/list',
    '/api/v2/topics/permissions/update'           => '/api/v2/topics/~topics_id~/permissions/update',
    '/api/v2/topics/permissions/user_list'        => '/api/v2/topics/permissions/user/list',
    '/api/v2/topics/reset'                        => '/api/v2/topics/~topics_id~/reset',
    '/api/v2/topics/sentences/count'              => '/api/v2/topics/~topics_id~/sentences/count',
    '/api/v2/topics/snapshots/generate'           => '/api/v2/topics/~topics_id~/snapshots/generate',
    '/api/v2/topics/snapshots/generate_status'    => '/api/v2/topics/~topics_id~/snapshots/generate_status',
    '/api/v2/topics/snapshots/list'               => '/api/v2/topics/~topics_id~/snapshots/list',
    '/api/v2/topics/snapshots/word2vec_model' => '/api/v2/topics/~topics_id~/snapshots/~dummy_id~/word2vec_model/~dummy_id~',
    '/api/v2/topics/stories/count'            => '/api/v2/topics/~topics_id~/stories/count',
    '/api/v2/topics/stories/facebook'         => '/api/v2/topics/~topics_id~/stories/facebook',
    '/api/v2/topics/stories/list'             => '/api/v2/topics/~topics_id~/stories/list',
    '/api/v2/topics/timespans/list'           => '/api/v2/topics/~topics_id~/timespans/list',
    '/api/v2/topics/update'                   => '/api/v2/topics/~topics_id~/update',
    '/api/v2/topics/spider'                   => '/api/v2/topics/~topics_id~/spider',
    '/api/v2/topics/spider_status'            => '/api/v2/topics/~topics_id~/spider_status',
    '/api/v2/topics/wc/list'                  => '/api/v2/topics/~topics_id~/wc/list',
};

# request GET, POST, and PUT methods from the url; return all responses that are not a 405
sub request_all_methods($;$)
{
    my ( $url, $params ) = @_;

    $params ||= {};
    $params->{ quit_after_auth } = 1;

    my $params_url = "$url?" . join( '&', map { "$_=" . uri_escape( $params->{ $_ } ) } keys( %{ $params } ) );

    my $methods = [ 'GET', 'POST', 'PUT' ];
    my $responses = [];

    foreach my $method ( @{ $methods } )
    {
        my $request = HTTP::Request->new( $method, $params_url );

        # Catalyst::Test::request()
        my $response = request( $request );
        push( @{ $responses }, $response );
    }

    return [ grep { $_->code != 405 } @{ $responses } ];
}

# make sure that the path requires at least a public key
sub test_key_required($)
{
    my ( $url ) = @_;

    my $responses = request_all_methods( $url );

    for my $response ( @{ $responses } )
    {
        my $method = $response->request->method;
        is( $response->code, 403, "test_key_required 403: $url $method" );
        ok( $response->decoded_content =~ /Invalid API key/, "test_key_required message: $url $method" );
    }
}

sub request_all_methods_as_user($$)
{
    my ( $url, $user ) = @_;

    return request_all_methods( $url, { key => $user->global_api_key() } );
}

# test whether the user has permission to request the url; if $expect_pass is true, expect that the user is allowed
# to request the page, otherwise espect that the user request is denied
sub test_user_permission
{
    my ( $url, $user, $expect_pass, $message ) = @_;

    my $responses = request_all_methods_as_user( $url, $user );

    my $expected_code = $expect_pass ? 200 : 403;

    map { ok( $_->code == $expected_code, "$message - $url: " . $_->decoded_content ) } @{ $responses };
}

# test a page with one of the permission types in the $permission_roles hash below.  verify that only
# the roles in the permission_roles table have access to the page.  create a new user for each
# tested user as needed.
sub test_role_permission($$$)
{
    my ( $db, $url, $permission_type ) = @_;

    my $permission_roles = {
        'admin'        => [ qw/admin/ ],
        'admin_read'   => [ qw/admin admin-readonly/ ],
        'media_edit'   => [ qw/admin media-edit/ ],
        'stories_edit' => [ qw/admin stories-edit media-edit/ ],
        'public'       => [ qw/admin admin-readonly media-edit stories-edit/ ]
    };

    my $permitted_roles = $permission_roles->{ $permission_type }
      || die( "unknown permission type '$permission_type'" );

    $url = transform_url( $url );

    test_key_required( $url );

    my $all_roles = {};
    for my $r ( values( %{ $permission_roles } ) )
    {
        map { $all_roles->{ $_ } = 1 } @{ $r };
    }

    for my $role ( keys( %{ $all_roles } ) )
    {
        my $user = find_or_add_test_user( $db, $role );
        my $role_has_permission = grep { $_ eq $role } @{ $permitted_roles };
        test_user_permission( $url, $user, $role_has_permission,
            "role permission for $url / $permission_type / $role / permitted: $role_has_permission" );
    }

    test_user_permission( $url, $_public_user, $permission_type eq 'public', "public user accepted for public url $url" );
}

# use $_url_transformations to insert any necessary ids into the given url
sub transform_url($;$)
{
    my ( $url, $topic ) = @_;

    my $model = $_url_transformations->{ $url };

    return $url unless ( $model );

    my $topics_id = $topic->{ topics_id } || '';

    $model =~ s/~topics_id~/$topics_id/xg;
    $model =~ s/~dummy_id~/1/g;

    die( "Unknown transformation: $model" ) if ( $model =~ /~/ );

    return $model;
}

sub test_topics_read_permission($)
{
    my ( $url ) = @_;

    for my $topic ( $_topic_a, $_topic_b )
    {
        my $topic_url = transform_url( $url, $topic );

        test_key_required( $topic_url );

        test_user_permission( $topic_url, $_public_user,          0, "public user rejected for topic" );
        test_user_permission( $topic_url, $topic->{ read_user },  1, "topic read user accepted for topic" );
        test_user_permission( $topic_url, $topic->{ write_user }, 1, "topic write user accepted for topic" );
        test_user_permission( $topic_url, $topic->{ admin_user }, 1, "topic admin user accepted for topic" );
    }

    my $public_topic_url = transform_url( $url, $_public_topic );
    test_user_permission( $public_topic_url, $_public_user, 1, "public user accepted for public topic" );
}

sub test_topics_write_permission($)
{
    my ( $url ) = @_;

    for my $topic ( $_topic_a, $_topic_b )
    {
        my $topic_url = transform_url( $url, $topic );

        test_key_required( $topic_url );

        test_user_permission( $topic_url, $_public_user,          0, "public user rejected for topic" );
        test_user_permission( $topic_url, $topic->{ read_user },  0, "topic read user rejected for topic" );
        test_user_permission( $topic_url, $topic->{ write_user }, 1, "topic write user accepted for topic" );
        test_user_permission( $topic_url, $topic->{ admin_user }, 1, "topic admin user accepted for topic" );
    }

    my $public_topic_url = transform_url( $url, $_public_topic );
    test_user_permission( $public_topic_url, $_public_user, 0, "public user rejected for public topic" );
}

sub test_topics_admin_permission($)
{
    my ( $url ) = @_;

    for my $topic ( $_topic_a, $_topic_b )
    {
        my $topic_url = transform_url( $url, $topic );

        test_key_required( $topic_url );

        test_user_permission( $topic_url, $_public_user,          0, "public user rejected for topic" );
        test_user_permission( $topic_url, $topic->{ read_user },  0, "topic read user rejected for topic" );
        test_user_permission( $topic_url, $topic->{ write_user }, 0, "topic write user rejected for topic" );
        test_user_permission( $topic_url, $topic->{ admin_user }, 1, "topic admin user accepted for topic" );
    }

    my $public_topic_url = transform_url( $url, $_public_topic );
    test_user_permission( $public_topic_url, $_public_user, 0, "public user rejected for public topic" );
}

# test that the url follows the rules for its permission type
sub test_permission($$)
{
    my ( $db, $url ) = @_;

    my $permission_type = $_url_permission_types->{ $url };

    ok( $permission_type, "permission type exists for $url" );

    return unless ( $permission_type );

    if    ( $permission_type eq 'topics_read' )  { test_topics_read_permission( $url ) }
    elsif ( $permission_type eq 'topics_write' ) { test_topics_write_permission( $url ) }
    elsif ( $permission_type eq 'topics_admin' ) { test_topics_admin_permission( $url ) }
    else                                         { test_role_permission( $db, $url, $permission_type ) }
}

# find or add user with email $role@foo.bar.  if $role corresponds to a row in auth_roles, add the auth_role to the user
sub find_or_add_test_user($$)
{
    my ( $db, $role ) = @_;

    my $email    = $role . '@foo.bar';
    my $password = '123456789';

    my $user;
    eval { $user = MediaWords::DBI::Auth::Profile::user_info( $db, $email ); };
    if ( ( !$@ ) and $user )
    {
        return $user;
    }

    my $roles = $db->query( "select auth_roles_id from auth_roles where role = ?", $role )->flat;

    eval {
        my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
            email           => $email,
            full_name       => $role,
            notes           => $role,
            role_ids        => $roles,
            active          => 1,
            password        => $password,
            password_repeat => $password,
            activation_url  => '',          # user is active, no need for activation URL
        );

        MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
    };
    if ( $@ )
    {
        die( "error adding $role user: $@" );
    }

    return MediaWords::DBI::Auth::Profile::user_info( $db, $email );
}

# add and return a test user with the given permission for the given topic.
sub add_topic_user($$$)
{
    my ( $db, $topic, $permission ) = @_;

    my $user = find_or_add_test_user( $db, "topic $topic->{ name } $permission" );

    $db->create(
        'topic_permissions',
        {
            topics_id     => $topic->{ topics_id },
            auth_users_id => $user->id(),
            permission    => $permission
        }
    );

    return $user;
}

# add a topic with the given public status; add 'read_user', 'write_user', 'admin_user' fields with a new
# user with each of the permissions
sub add_topic
{
    my ( $db, $name, $is_public ) = @_;

    my $tag_set = $db->create( 'tag_sets', { name => $name } );

    my $topic = {
        name            => $name,
        pattern         => $name,
        solr_seed_query => $name,
        description     => $name,
        is_public       => normalize_boolean_for_db( $is_public ),
        start_date      => '2017-01-01',
        end_date        => '2017-02-01',
        job_queue       => 'mc',
        max_stories     => 100_000,
    };

    $topic = $db->create( 'topics', $topic );

    $topic->{ read_user }  = add_topic_user( $db, $topic, 'read' );
    $topic->{ write_user } = add_topic_user( $db, $topic, 'write' );
    $topic->{ admin_user } = add_topic_user( $db, $topic, 'admin' );

    return $topic;
}

# for each path, test to make sure that at least a public key is required, then check to make sure the expected
# permission is required for the path
sub test_permissions($$)
{
    my ( $db ) = @_;

    my $api_urls = MediaWords::Test::API::get_api_urls();

    $_public_user = find_or_add_test_user( $db, 'public' );

    $_public_topic = add_topic( $db, 'public topic', 1 );
    $_topic_a      = add_topic( $db, 'topic a' );
    $_topic_b      = add_topic( $db, 'topic b' );

    for my $url ( @{ $api_urls } )
    {
        test_permission( $db, $url );
    }
}

sub main()
{

    MediaWords::Test::DB::test_on_test_database( \&test_permissions );

    done_testing();
}

main();
