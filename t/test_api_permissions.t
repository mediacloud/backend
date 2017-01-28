#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin";
    use lib "$FindBin::Bin/../lib";
    use Catalyst::Test 'MediaWords';
}

use MediaWords::CommonLibs;
use Modern::Perl "2015";

use HTTP::Request::Common;
use JSON;
use List::MoreUtils "uniq";
use List::Util "shuffle";
use Readonly;
use Test::More;
use URI::Escape;

use MediaWords::Test::DB;

# public and admin_read key users
my $_public_user;

# test topics
my $_public_topic;
my $_topic_a;
my $_topic_b;

# this hash maps each api end point to the kind of permission it should have: public, admin_read, or topics
my $_url_permission_types = {
    '/api/v2/auth/single'                         => 'admin_read',
    '/api/v2/auth/profile'                        => 'public',
    '/api/v2/controversies/list'                  => 'public',
    '/api/v2/controversies/single'                => 'public',
    '/api/v2/controversy_dumps/list'              => 'public',
    '/api/v2/controversy_dumps/single'            => 'public',
    '/api/v2/controversy_dump_time_slices/list'   => 'public',
    '/api/v2/controversy_dump_time_slices/single' => 'public',
    '/api/v2/crawler/add_feed_download'           => 'admin',
    '/api/v2/downloads/list'                      => 'admin_read',
    '/api/v2/downloads/single'                    => 'admin_read',
    '/api/v2/feeds/list'                          => 'public',
    '/api/v2/feeds/scrape'                        => 'media_edit',
    '/api/v2/feeds/scrape_status'                 => 'media_edit',
    '/api/v2/feeds/single'                        => 'public',
    '/api/v2/feeds/create'                        => 'media_edit',
    '/api/v2/feeds/update'                        => 'media_edit',
    '/api/v2/mc_rest_simpleobject/list'           => 'public',
    '/api/v2/mc_rest_simpleobject/single'         => 'public',
    '/api/v2/mediahealth/list'                    => 'public',
    '/api/v2/mediahealth/single'                  => 'public',
    '/api/v2/media/list'                          => 'public',
    '/api/v2/media/single'                        => 'public',
    '/api/v2/media/create'                        => 'media_edit',
    '/api/v2/media/put_tags'                      => 'media_edit',
    '/api/v2/media/update'                        => 'media_edit',
    '/api/v2/media/mark_suggestion'               => 'media_edit',
    '/api/v2/media/list_suggestions'              => 'media_edit',
    '/api/v2/media/submit_suggestion'             => 'public',
    '/api/v2/sentences/count'                     => 'public',
    '/api/v2/sentences/field_count'               => 'public',
    '/api/v2/sentences/list'                      => 'admin_read',
    '/api/v2/sentences/put_tags'                  => 'stories_edit',
    '/api/v2/sentences/single'                    => 'admin_read',
    '/api/v2/stats/list'                          => 'public',
    '/api/v2/storiesbase/count'                   => 'public',
    '/api/v2/storiesbase/list'                    => 'public',
    '/api/v2/storiesbase/single'                  => 'public',
    '/api/v2/storiesbase/word_matrix'             => 'public',
    '/api/v2/stories/cluster_stories'             => 'admin_read',
    '/api/v2/stories/corenlp'                     => 'admin_read',
    '/api/v2/stories/count'                       => 'public',
    '/api/v2/stories/fetch_bitly_clicks'          => 'admin_read',
    '/api/v2/stories/list'                        => 'admin_read',
    '/api/v2/stories_public/count'                => 'public',
    '/api/v2/stories_public/list'                 => 'public',
    '/api/v2/stories_public/single'               => 'public',
    '/api/v2/stories_public/word_matrix'          => 'public',
    '/api/v2/stories/put_tags'                    => 'stories_edit',
    '/api/v2/stories/single'                      => 'admin_read',
    '/api/v2/stories/word_matrix'                 => 'public',
    '/api/v2/tag_sets/list'                       => 'public',
    '/api/v2/tag_sets/single'                     => 'public',
    '/api/v2/tag_sets/update'                     => 'admin',
    '/api/v2/tag_sets/create'                     => 'admin',
    '/api/v2/tags/list'                           => 'public',
    '/api/v2/tags/single'                         => 'public',
    '/api/v2/tags/update'                         => 'admin',
    '/api/v2/tags/create'                         => 'admin',
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
    '/api/v2/topics/sentences/count'              => 'topics_read',
    '/api/v2/topics/single'                       => 'public',
    '/api/v2/topics/create'                       => 'media_edit',
    '/api/v2/topics/update'                       => 'topics_write',
    '/api/v2/topics/snapshots/generate'           => 'topics_write',
    '/api/v2/topics/snapshots/list'               => 'topics_read',
    '/api/v2/topics/stories/count'                => 'topics_read',
    '/api/v2/topics/stories/list'                 => 'topics_read',
    '/api/v2/topics/timespans/list'               => 'topics_read',
    '/api/v2/topics/wc/list'                      => 'topics_read',
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
    '/api/v2/topics/sentences/count'              => '/api/v2/topics/~topics_id~/sentences/count',
    '/api/v2/topics/snapshots/generate'           => '/api/v2/topics/~topics_id~/snapshots/generate',
    '/api/v2/topics/snapshots/list'               => '/api/v2/topics/~topics_id~/snapshots/list',
    '/api/v2/topics/stories/count'                => '/api/v2/topics/~topics_id~/stories/count',
    '/api/v2/topics/stories/list'                 => '/api/v2/topics/~topics_id~/stories/list',
    '/api/v2/topics/timespans/list'               => '/api/v2/topics/~topics_id~/timespans/list',
    '/api/v2/topics/wc/list'                      => '/api/v2/topics/~topics_id~/wc/list',
};

# request GET, POST, and PUT methods from the url; return all responses that are not a 405
sub request_all_methods($;$)
{
    my ( $url, $params ) = @_;

    $params ||= {};
    $params->{ quit_after_auth } = 1;

    my $params_url = "$url?" . join( '&', map { "$_=" . uri_escape( $params->{ $_ } ) } keys( %{ $params } ) );

    my $responses = [ map { request( $_ ) } ( PUT( $params_url ), POST( $params_url ), GET( $params_url ) ) ];

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

# query the catalyst context to get a list of urls of all api end points
sub get_api_urls()
{
    # use any old request just to get the $c
    my ( $res, $c ) = ctx_request( '/admin/topics/list' );

    # this chunk of code that pulls url end points out of catalyst relies on ugly reverse engineering of the
    # private internals of the Catalyst::DispatchType::Chained and Catalyst::DispathType::Path, but it is as
    # far as I can tell the only way to get catalyst to tell us what urls it is serving.

    my $chained_actions = $c->dispatcher->dispatch_type( 'Chained' )->_endpoints;
    my $chained_urls = [ map { "/$_->{ reverse }" } @{ $chained_actions } ];

    my $path_actions = [ values( %{ $c->dispatcher->dispatch_type( 'Path' )->_paths } ) ];
    my $path_urls = [ map { $_->[ 0 ]->private_path } @{ $path_actions } ];

    my $api_urls = [ sort grep { m~/api/~ } ( @{ $path_urls }, @{ $chained_urls } ) ];

    return $api_urls;
}

sub request_all_methods_as_user($$)
{
    my ( $url, $user ) = @_;

    return request_all_methods( $url, { key => $user->{ api_token } } );
}

# test whether the user has permission to request the url; if $expect_pass is true, expect that the user is allowed
# to request the page, otherwise espect that the user request is denied
sub test_user_permission
{
    my ( $url, $user, $expect_pass, $message ) = @_;

    my $responses = request_all_methods_as_user( $url, $user );

    my $expected_code = $expect_pass ? 200 : 403;

    map { ok( $_->code == $expected_code, "$message - $url: " . $_->as_string ) } @{ $responses };
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

    $model =~ s/~topics_id~/$topic->{ topics_id }/xg;
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

    my $user = $db->query( "select * from auth_users where email = ?", $email )->hash;

    return $user if ( $user );

    my $roles = $db->query( "select auth_roles_id from auth_roles where role = ?", $role )->flat;

    my $error = MediaWords::DBI::Auth::add_user_or_return_error_message( $db, $email, $role, $role, $roles, 1,
        $password, $password, 10000000, 10000000 );

    die( "error adding $role user: $error" ) if ( $error );

    return $db->query( "select * from auth_users where email = ?", $email )->hash;
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
            auth_users_id => $user->{ auth_users_id },
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
        name              => $name,
        pattern           => $name,
        solr_seed_query   => $name,
        description       => $name,
        topic_tag_sets_id => $tag_set->{ tag_sets_id },
        is_public         => $is_public ? 1 : 0
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
    my ( $db, $api_urls ) = @_;

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
    MediaWords::Test::DB::test_on_test_database(
        sub {

            my $db = shift;

            my $api_urls = get_api_urls();

            test_permissions( $db, $api_urls );

            done_testing();
        }
    );
}

main();
