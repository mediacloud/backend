use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use MediaWords::Test::HashServer;
use Readonly;
use Test::More;
use Test::Deep;

use MediaWords::DB;
use MediaWords::Test::API;
use MediaWords::Test::Rows;
use MediaWords::Test::Solr;
use MediaWords::Test::URLs;
use MediaWords::Test::DB::Create;
use MediaWords::Util::SQL;
use MediaWords::Util::Tags;

Readonly my $NUM_MEDIA            => 5;
Readonly my $NUM_FEEDS_PER_MEDIUM => 2;
Readonly my $NUM_STORIES_PER_FEED => 10;

# test that the media/list call with the given params returns precisely the list of expected media
sub test_media_list_call($$)
{
    my ( $params, $expected_media ) = @_;

    my $d = Data::Dumper->new( [ $params ] );
    $d->Terse( 1 );
    my $label = "media/list with params " . $d->Dump;

    my $got_media = MediaWords::Test::API::test_get( '/api/v2/media/list', $params );

    is( scalar( @{ $got_media } ), scalar( @{ $expected_media } ), "$label number of media" );
    for my $got_medium ( @{ $got_media } )
    {
        my ( $expected_medium ) = grep { $_->{ media_id } eq $got_medium->{ media_id } } @{ $expected_media };
        ok( $expected_medium, "$label medium $got_medium->{ media_id } expected" );

        my $fields = [ qw/name url is_healthy is_monitored editor_notes public_notes/ ];
        map { ok( defined( $got_medium->{ $_ } ), "$label field $_ defined" ) } @{ $fields };
        map { is( $got_medium->{ $_ }, $expected_medium->{ $_ }, "$label field $_" ) } @{ $fields };

        if ( my $tag = $got_medium->{ media_source_tags }->[ 0 ] )
        {
            my $today = substr( MediaWords::Util::SQL::sql_now(), 0, 10 );
            is( $tag->{ tagged_date }, $today, 'tagged date' );
        }
    }
}

# test the media/list call
sub test_media_list($$)
{
    my ( $db, $test_stack ) = @_;

    my $test_stack_media = [ grep { defined( $_->{ foreign_rss_links } ) } values( %{ $test_stack } ) ];
    die( "no media found: " . Dumper( $test_stack ) ) unless ( @{ $test_stack_media } );

    # this has to be done first so that media_health exists
    map { $_->{ is_healthy } = 1 } @{ $test_stack_media };
    my $unhealthy_medium = $test_stack_media->[ 2 ];
    $unhealthy_medium->{ is_healthy } = 0;
    $db->query( "update media_health set is_healthy = ( media_id <> \$1 )", $unhealthy_medium->{ media_id } );
    test_media_list_call( { unhealthy => 1 }, [ $unhealthy_medium ] );

    test_media_list_call( {}, $test_stack_media );

    my $single_medium = $test_stack_media->[ 0 ];
    test_media_list_call( { name => $single_medium->{ name } }, [ $single_medium ] );

    my $got_single_medium = MediaWords::Test::API::test_get( '/api/v2/media/single/' . $single_medium->{ media_id }, {} );
    my $fields = [ qw/name url is_healthy is_monitored editor_notes public_notes/ ];
    MediaWords::Test::Rows::rows_match( $db, $got_single_medium, [ $single_medium ], 'media_id', $fields );

    my $tagged_medium = $test_stack_media->[ 1 ];
    my $test_tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'media_list_test:media_list_test' );
    $db->update_by_id( 'tags', $test_tag->{ tags_id }, { show_on_media => 't' } );
    $db->create( 'media_tags_map', { tags_id => $test_tag->{ tags_id }, media_id => $tagged_medium->{ media_id } } );
    test_media_list_call( { tag_name => $test_tag->{ tag } }, [ $tagged_medium ] );

    my $similar_medium = $test_stack_media->[ 2 ];
    $db->create( 'media_tags_map', { tags_id => $test_tag->{ tags_id }, media_id => $similar_medium->{ media_id } } );
    test_media_list_call( { similar_media_id => $tagged_medium->{ media_id } }, [ $similar_medium ] );
}

# wait for feed scraping to happen and verify that a valid feed has been discovered for each site
sub test_for_scraped_feeds($$)
{
    my ( $db, $sites ) = @_;

    my $timeout = 90;
    my $i       = 0;
    while ( $i++ < $timeout )
    {
        my ( $num_waiting_media ) =
          $db->query( "select count(*) from media_rescraping where last_rescrape_time is null" )->flat;
        ( $num_waiting_media > 0 ) ? sleep 1 : last;
        DEBUG( "wait for feed scraping ($num_waiting_media) ..." );
    }

    ok( 0, "timed out waiting for scraped feeds" ) if ( $i == $timeout );

    for my $site ( @{ $sites } )
    {
        my $medium = $db->query( "select * from media where name = ?", $site->{ name } )->hash
          || die( "unable to find medium for site $site->{ name }" );
        my $feed = $db->query( "select * from feeds where media_id = ?", $medium->{ media_id } )->hash;
        ok( $feed, "feed exists for site $site->{ name } media_id $medium->{ media_id }" );
        is( $feed->{ type }, 'syndicated', "$site->{ name } feed type" );
        ok( $feed->{ active }, "$site->{ name } feed is active" );
        is_urls( $feed->{ url }, $site->{ feed_url }, "$site->{ name } feed url" );
    }
}

# start a MediaWords::Test::HashServer with the following pages for each of the given site names:
# * home page - http://localhost:$port/$site
# * feed page - http://localhost:$port/$site/feed
# * custom feed page - http://localhost:$port/$site/custom_feed
#
# return the MediaWords::Test::HashServer instance
sub _start_media_create_hash_server
{
    my ( $site_names ) = @_;

    my $port = 8976;

    my $pages = {};
    for my $site_name ( @{ $site_names } )
    {
        $pages->{ "/$site_name" } = "<html><title>$site_name</title><body>$site_name body</body>";

        my $atom = <<ATOM;
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
    <title>$site_name</title>
    <link href="http://localhost:$port/$site_name" />
    <id>urn:uuid:60a76c80-d399-11d9-b91C-0003939e0af6</id>
    <updated>2015-12-13T18:30:02Z</updated>
    <entry>
        <title>$site_name page</title>
        <link href="http://localhost:$port/$site_name/page" />
        <id>urn:uuid:1225c695-cfb8-4ebb-aaaa-80da344efa6a</id>
        <updated>2015-12-13T18:30:02Z</updated>
    </entry>
</feed>
ATOM

        $pages->{ "/$site_name/feed" }        = { header => 'Content-Type: application/atom+xml', content => $atom };
        $pages->{ "/$site_name/custom_feed" } = { header => 'Content-Type: application/atom+xml', content => $atom };
    }

    my $hs = MediaWords::Test::HashServer->new( $port, $pages );

    $hs->start();

    return $hs;
}

# test that the feeds and tags_ids fields update existing media sources when passed to create
sub test_media_create_update($$)
{
    my ( $db, $sites ) = @_;

    my $tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'media_test:media_test' );

    my $input = [
        map {
            {
                url      => $_->{ url },
                tags_ids => [ $tag->{ tags_id } ],
                feeds    => [ $_->{ feed_url }, $_->{ custom_feed_url }, 'http://127.0.0.1:12345/456789/feed' ]
            }
        } @{ $sites }
    ];

    my $r = MediaWords::Test::API::test_post( '/api/v2/media/create', $input );

    my $got_media_ids = [ map { $_->{ media_id } } grep { $_->{ status } ne 'error' } @{ $r } ];
    is( scalar( @{ $got_media_ids } ), scalar( @{ $sites } ), "media/create update media returned" );

    for my $site ( @{ $sites } )
    {
        my $medium = $db->query( "select * from media where name = ?", $site->{ name } )->hash
          || die( "unable to find medium for site $site->{ name }" );
        my $feeds = $db->query( "select * from feeds where media_id = ? order by feeds_id", $medium->{ media_id } )->hashes;
        is( scalar( @{ $feeds } ), 2, "media/create update $site->{ name } num feeds" );

        is_urls( $feeds->[ 0 ]->{ url }, $site->{ feed_url }, "media/create update $site->{ name } default feed url" );
        is_urls( $feeds->[ 1 ]->{ url }, $site->{ custom_feed_url }, "media/create update $site->{ name } custom feed url" );

        for my $feed ( @{ $feeds } )
        {
            is( $feed->{ type }, 'syndicated', "$site->{ name } feed type" );
            ok( $feed->{ active }, "$site->{ name } feed is active" );
        }

        my ( $tag_exists ) = $db->query( <<SQL, $medium->{ media_id }, $tag->{ tags_id } )->flat;
select * from media_tags_map where media_id = \$1 and tags_id = \$2
SQL
        ok( $tag_exists, "media/create update $site->{ name } tag exists" );
    }
}

# test media/update call
sub test_media_update($$)
{
    my ( $db, $sites ) = @_;

    # test that request with no media_id returns an error
    MediaWords::Test::API::test_put( '/api/v2/media/update', {}, 1 );

    # test that request with list returns an error
    MediaWords::Test::API::test_put( '/api/v2/media/update', [ { media_id => 1 } ], 1 );

    my $medium = $db->query( "select * from media where name = ?", $sites->[ 0 ]->{ name } )->hash;

    my $fields = [ qw/media_id name url content_delay editor_notes public_notes foreign_rss_links/ ];

    # test just name change
    my $r = MediaWords::Test::API::test_put( '/api/v2/media/update', { media_id => $medium->{ media_id }, name => "$medium->{ name } FOO" } );
    is( $r->{ success }, 1, "media/update name success" );

    my $updated_medium = $db->require_by_id( 'media', $medium->{ media_id } );
    is( $updated_medium->{ name }, "$medium->{ name } FOO", "media update name" );
    $medium->{ name } = $updated_medium->{ name };
    map { is( $updated_medium->{ $_ }, $medium->{ $_ }, "media update name field $_" ) } @{ $fields };

    # test all other fields
    $medium = {
        media_id          => $medium->{ media_id },
        url               => "http://url.update/",
        name              => 'name update',
        foreign_rss_links => 1,
        content_delay     => 100,
        editor_notes      => 'editor_notes update',
        public_notes      => 'public_notes update'
    };

    $r = MediaWords::Test::API::test_put( '/api/v2/media/update', $medium );
    is( $r->{ success }, 1, "media/update all success" );

    $updated_medium = $db->require_by_id( 'media', $medium->{ media_id } );
    map { is( $updated_medium->{ $_ }, $medium->{ $_ }, "media update name field $_" ) } @{ $fields };
}

# test media/create end point
sub test_media_create($)
{
    my ( $db ) = @_;

    my $site_names = [ map { "media_create_site_$_" } ( 1 .. 5 ) ];

    my $hs = _start_media_create_hash_server( $site_names );

    my $sites = [];
    for my $site_name ( @{ $site_names } )
    {
        push(
            @{ $sites },
            {
                name            => $site_name,
                url             => $hs->page_url( $site_name ),
                feed_url        => $hs->page_url( "$site_name/feed" ),
                custom_feed_url => $hs->page_url( "$site_name/custom_feed" )
            }
        );
    }

    # delete existing entries in media_rescraping so that we can wait for it to be empty in test_for_scraped_feeds()
    $db->query( "truncate table media_rescraping" );

    # test that non-list returns an error
    MediaWords::Test::API::test_post( '/api/v2/media/create', {}, 1 );

    # test that single element without url returns an error
    MediaWords::Test::API::test_post( '/api/v2/media/create', [ { url => 'http://foo.com' }, { name => "bar" } ], 1 );

    # simple test for creation of url only medium
    my $first_site = $sites->[ 0 ];
    my $r = MediaWords::Test::API::test_post( '/api/v2/media/create', [ { url => $first_site->{ url } } ] );

    is( scalar( @{ $r } ),     1,     "media/create url number of statuses" );
    is( $r->[ 0 ]->{ status }, 'new', "media/create url status" );
    is_urls( $r->[ 0 ]->{ url }, $first_site->{ url }, "media/create url url" );

    my $first_medium = $db->query( "select * from media where name = \$1", $first_site->{ name } )->hash;
    ok( $first_medium, "media/create url found medium with matching title" );

    # test that create reuse the same media source we just created
    $r = MediaWords::Test::API::test_post( '/api/v2/media/create', [ { url => $first_site->{ url } } ] );
    is( scalar( @{ $r } ),     1,          "media/create existing number of statuses" );
    is( $r->[ 0 ]->{ status }, 'existing', "media/create existing status" );
    is_urls( $r->[ 0 ]->{ url }, $first_site->{ url }, "media/create existing url" );
    is( $r->[ 0 ]->{ media_id }, $first_medium->{ media_id }, "media/create existing media_id" );

    # add all media sources in sites, plus one which should return a 404
    my $input = [ map { { url => $_->{ url } } } ( @{ $sites }, { url => 'http://127.0.0.1:12345/456789' } ) ];
    $r = MediaWords::Test::API::test_post( '/api/v2/media/create', $input );
    my $status_media_ids = [ map { $_->{ media_id } } grep { $_->{ status } ne 'error' } @{ $r } ];
    my $status_errors    = [ map { $_->{ error } } grep    { $_->{ status } eq 'error' } @{ $r } ];

    is( scalar( @{ $status_media_ids } ), scalar( @{ $sites } ), "media/create mixed urls number returned" );
    is( scalar( @{ $status_errors } ), 1, "media/create mixed urls errors returned" );
    ok( $status_errors->[ 0 ] =~ /Unable to fetch medium url/, "media/create mixed urls error message" );

    for my $site ( @{ $sites } )
    {
        my $url = $site->{ url };
        my $db_m = $db->query( "select * from media where url = ?", $url )->hash;
        ok( $db_m, "media/create mixed urls medium found for in db url $url" );
        ok( grep { $_ == $db_m->{ media_id } } @{ $status_media_ids } );
    }

    test_for_scraped_feeds( $db, $sites );

    test_media_create_update( $db, $sites );

    test_media_update( $db, $sites );

    $hs->stop();
}

# test the media/submit_suggestion call
sub test_media_suggestions_submit($)
{
    my ( $db ) = @_;

    # make sure url is required
    MediaWords::Test::API::test_post( '/api/v2/media/submit_suggestion', {}, 1 );

    # test with simple url
    my $simple_url = 'http://foo.com';
    MediaWords::Test::API::test_post( '/api/v2/media/submit_suggestion', { url => $simple_url } );

    my $simple_ms = $db->query( "select * from media_suggestions where url = \$1", $simple_url )->hash;
    ok( $simple_ms, "media/submit_suggestion simple url found" );

    # test with all fields in input
    my $tag_1 = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'media_suggestions:tag_1' );
    my $tag_2 = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'media_suggestions:tag_2' );

    my $full_ms_input = {
        url      => 'http://bar.com',
        name     => 'foo',
        feed_url => 'http://feed.url',
        reason   => 'bar',
        tags_ids => [ map { $_->{ tags_id } } ( $tag_1, $tag_2 ) ]
    };

    MediaWords::Test::API::test_post( '/api/v2/media/submit_suggestion', $full_ms_input );

    my $full_ms_db = $db->query( "select * from media_suggestions where url = \$1", $full_ms_input->{ url } )->hash;
    ok( $full_ms_db, "media/submit_suggestion full input found" );

    for my $field ( qw/name feed_url reason/ )
    {
        is( $full_ms_db->{ $field }, $full_ms_input->{ $field }, "media/submit_suggestion full input $field" );
    }

    ok( $full_ms_db->{ date_submitted }, "media/submit_suggestion full date_submitted set" );

    for my $tag ( $tag_1, $tag_2 )
    {
        my $tag_exists = $db->query( <<SQL, $tag->{ tags_id }, $full_ms_db->{ media_suggestions_id } )->hash;
select * from media_suggestions_tags_map where tags_id = \$1 and media_suggestions_id = \$2
SQL
        ok( $tag_exists, "media/submit_suggestion full tag $tag->{ tags_id } exists" );
    }
}

# test that the media/list_suggestions call with the given $call_params returned the given results
sub test_suggestions_list_results($$$)
{
    my ( $label, $call_params, $expected_results ) = @_;

    $label = "media/list_suggestions $label";

    my $expected_num = scalar( @{ $expected_results } );

    my $r = MediaWords::Test::API::test_get( '/api/v2/media/list_suggestions', $call_params );
    my $got_mss = $r->{ media_suggestions };
    ok( $got_mss, "$label media_suggestions set" );

    is( scalar( @{ $got_mss } ), $expected_num, "$label number returned" );

    my $prev_id = 0;
    for my $got_ms ( @{ $got_mss } )
    {
        my ( $expected_ms ) =
          grep { $_->{ media_suggestions_id } == $got_ms->{ media_suggestions_id } } @{ $expected_results };
        ok( $expected_ms, "$label returned ms $got_ms->{ media_suggestions_id } matches db row" );
        for my $field ( qw/status url name feed_url reason media_id mark_reason user/ )
        {
            is( $got_ms->{ $field }, $expected_ms->{ $field }, "$label field $field" );
        }
        ok( $got_ms->{ media_suggestions_id } > $prev_id, "$label media_ids in order" );
        $prev_id = $got_ms->{ media_suggestions_id };
    }

}

# test media/list_suggestions
sub test_media_suggestions_list($)
{
    my ( $db ) = @_;

    my $num_status_ms = 10;

    my ( $auth_users_id, $email ) = $db->query( "select auth_users_id from auth_users limit 1" )->flat;

    my $ms_db     = [];
    my $media_ids = $db->query( "select media_id from media" )->flat;

    my $tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, "media_suggestions:test_tag" );

    for my $status ( qw/pending approved rejected/ )
    {
        for my $i ( 1 .. $num_status_ms )
        {
            my $ms = {
                url           => "http://m.s/$i",
                name          => "ms $i",
                feed_url      => "http://feed.m.s/$i",
                auth_users_id => $auth_users_id,
                reason        => "reason $i",
                status        => $status,
            };

            if ( $status ne 'pending' )
            {
                $ms->{ mark_reason } = "mark reason $i";
                $ms->{ date_marked } = MediaWords::Util::SQL::sql_now;
            }

            if ( $status eq 'approved' )
            {
                $ms->{ media_id } = shift( @{ $media_ids } );
                push( @{ $media_ids }, $ms->{ media_id } );
            }

            $ms = $db->create( 'media_suggestions', $ms );

            $ms->{ email } = $email;

            if ( $i % 2 )
            {
                $ms->{ tags_id } = [ $tag->{ tags_id } ];
                $db->query( <<SQL, $ms->{ media_suggestions_id }, $tag->{ tags_id } );
insert into media_suggestions_tags_map ( media_suggestions_id, tags_id ) values ( \$1, \$2 )
SQL
            }

            push( @{ $ms_db }, $ms );
        }
    }

    test_suggestions_list_results( 'pending', {}, [ grep { $_->{ status } eq 'pending' } @{ $ms_db } ] );
    test_suggestions_list_results( 'all', { all => 1 }, $ms_db );

    my $pending_tags_ms = [ grep { $_->{ status } eq 'pending' && $_->{ tags_id } } @{ $ms_db } ];
    test_suggestions_list_results( 'pending + tags_id', { tags_id => $tag->{ tags_id } }, $pending_tags_ms );

}

# test media/mark_suggestion end point
sub test_media_suggestions_mark($)
{
    my ( $db ) = @_;

    my ( $auth_users_id ) = $db->query( "select auth_users_id from auth_users limit 1" )->flat;

    my $ms = {
        url           => "http://m.s/mark",
        name          => "ms mark",
        feed_url      => "http://feed.m.s/mark",
        auth_users_id => $auth_users_id,
        reason        => "reason mark"
    };
    $ms = $db->create( 'media_suggestions', $ms );
    my $ms_id = $ms->{ media_suggestions_id };

    # test for required status and media_suggestions_id
    MediaWords::Test::API::test_put( '/api/v2/media/mark_suggestion', {}, 1 );
    MediaWords::Test::API::test_put( '/api/v2/media/mark_suggestion', { media_suggestions_id => $ms_id }, 1 );
    MediaWords::Test::API::test_put( '/api/v2/media/mark_suggestion', { status => 'approved' }, 1 );

    # test for error on invalid input
    MediaWords::Test::API::test_put( '/api/v2/media/mark_suggestion', { media_suggestions_id => 0,      status => 'approved' },       1 );
    MediaWords::Test::API::test_put( '/api/v2/media/mark_suggestion', { media_suggestions_id => $ms_id, status => 'invalid_status' }, 1 );

    # test reject
    MediaWords::Test::API::test_put( '/api/v2/media/mark_suggestion',
        { media_suggestions_id => $ms_id, status => 'rejected', mark_reason => 'rejected' } );
    $ms = $db->require_by_id( 'media_suggestions', $ms_id );

    is( $ms->{ status },      'rejected', "media/mark_suggestion reject status" );
    is( $ms->{ mark_reason }, 'rejected', "media/mark_suggestion reject mark_reason" );

    my ( $media_id ) = $db->query( "select media_id from media limit 1" )->flat;

    # test approve
    my $approve_input = {
        media_suggestions_id => $ms_id,
        status               => 'approved',
        mark_reason          => 'approved'
    };

    # verify that approval with media_id causes error
    MediaWords::Test::API::test_put( '/api/v2/media/mark_suggestion', $approve_input, 1 );

    # now try valid submission
    $approve_input->{ media_id } = $media_id;
    MediaWords::Test::API::test_put( '/api/v2/media/mark_suggestion', $approve_input );
    $ms = $db->require_by_id( 'media_suggestions', $ms_id );

    is( $ms->{ status },      'approved', "media/mark_suggestion approve status" );
    is( $ms->{ mark_reason }, 'approved', "media/mark_suggestion approve mark_reason" );
    is( $ms->{ media_id },    $media_id,  'media/mark_suggestion approve media_id' );

    # now try setting back to pending
    MediaWords::Test::API::test_put( '/api/v2/media/mark_suggestion',
        { media_suggestions_id => $ms_id, status => 'pending', mark_reason => 'pending' } );
    $ms = $db->require_by_id( 'media_suggestions', $ms_id );

    is( $ms->{ status },      'pending', "media/mark_suggestion pending status" );
    is( $ms->{ mark_reason }, 'pending', "media/mark_suggestion pending mark_reason" );
}

# test media suggestions list, submit, and mark calls
sub test_media_suggestions($)
{
    my ( $db ) = @_;

    test_media_suggestions_list( $db );
    test_media_suggestions_submit( $db );
    test_media_suggestions_mark( $db );
}

sub test_media($)
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::DB::Create::create_test_story_stack_numerated( $db, $NUM_MEDIA, $NUM_FEEDS_PER_MEDIUM,
        $NUM_STORIES_PER_FEED );

    $media = MediaWords::Test::DB::Create::add_content_to_test_story_stack( $db, $media );

    MediaWords::Test::Solr::setup_test_index( $db );

    MediaWords::Test::API::setup_test_api_key( $db );

    test_media_list( $db, $media );
    test_media_create( $db );
    test_media_suggestions( $db );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_media( $db );

    done_testing();
}

main();
