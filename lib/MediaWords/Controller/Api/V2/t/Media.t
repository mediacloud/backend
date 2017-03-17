use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use HTTP::HashServer;
use Readonly;
use Test::More;
use Test::Deep;

use MediaWords::Test::API;
use MediaWords::Test::DB;
use MediaWords::Test::Solr;
use MediaWords::Test::Supervisor;

use MediaWords::DBI::Media::Health;
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

    my $got_media = test_get( '/api/v2/media/list', $params );
    is( scalar( @{ $got_media } ), scalar( @{ $expected_media } ), "$label number of media" );
    for my $got_medium ( @{ $got_media } )
    {
        my ( $expected_medium ) = grep { $_->{ media_id } eq $got_medium->{ media_id } } @{ $expected_media };
        ok( $expected_medium, "$label medium $got_medium->{ media_id } expected" );

        my $fields = [ qw/name url is_healthy is_monitored editor_notes public_notes/ ];
        map { ok( defined( $got_medium->{ $_ } ), "$label field $_ defined" ) } @{ $fields };
        map { is( $got_medium->{ $_ }, $expected_medium->{ $_ }, "$label field $_" ) } @{ $fields };

        is(
            $got_medium->{ primary_language }      || 'null',
            $expected_medium->{ primary_language } || 'null',
            "$label field primary language"
        );
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
    MediaWords::DBI::Media::Health::generate_media_health( $db );
    $db->query( "update media_health set is_healthy = ( media_id <> \$1 )", $unhealthy_medium->{ media_id } );
    test_media_list_call( { unhealthy => 1 }, [ $unhealthy_medium ] );

    test_media_list_call( {}, $test_stack_media );

    my $single_medium = $test_stack_media->[ 0 ];
    test_media_list_call( { name => $single_medium->{ name } }, [ $single_medium ] );

    my $got_single_medium = test_get( '/api/v2/media/single/' . $single_medium->{ media_id }, {} );
    my $fields = [ qw/name url is_healthy is_monitored editor_notes public_notes/ ];
    rows_match( $db, $got_single_medium, [ $single_medium ], 'media_id', $fields );

    my $tagged_medium = $test_stack_media->[ 1 ];
    my $test_tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'media_list_test:media_list_test' );
    $db->update_by_id( 'tags', $test_tag->{ tags_id }, { show_on_media => 't' } );
    $db->create( 'media_tags_map', { tags_id => $test_tag->{ tags_id }, media_id => $tagged_medium->{ media_id } } );
    test_media_list_call( { tag_name => $test_tag->{ tag } }, [ $tagged_medium ] );

    my $similar_medium = $test_stack_media->[ 2 ];
    $db->create( 'media_tags_map', { tags_id => $test_tag->{ tags_id }, media_id => $similar_medium->{ media_id } } );
    test_media_list_call( { similar_media_id => $tagged_medium->{ media_id } }, [ $similar_medium ] );

    my $english_medium = $test_stack_media->[ 1 ];
    $db->query( "update media set primary_language = 'en' where media_id = \$1", $english_medium->{ media_id } );
    $english_medium->{ primary_language } = 'en';
    test_media_list_call( { primary_language => 'en' }, [ $english_medium ] );
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
        is( $feed->{ feed_type },   'syndicated',        "$site->{ name } feed type" );
        is( $feed->{ feed_status }, 'active',            "$site->{ name } feed status" );
        is( $feed->{ url },         $site->{ feed_url }, "$site->{ name } feed url" );
    }
}

# start a HTTP::HashServer with the following pages for each of the given site names:
# * home page - http://localhost:$port/$site
# * feed page - http://localhost:$port/$site/feed
# * custom feed page - http://localhost:$port/$site/custom_feed
#
# return the HTTP::HashServer
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

    my $hs = HTTP::HashServer->new( $port, $pages );

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
                feeds    => [ $_->{ feed_url }, $_->{ custom_feed_url }, 'http://127.0.0.1:123456/456789/feed' ]
            }
        } @{ $sites }
    ];

    my $r = test_post( '/api/v2/media/create', $input );

    my $got_media_ids = [ map { $_->{ media_id } } grep { $_->{ status } ne 'error' } @{ $r } ];
    is( scalar( @{ $got_media_ids } ), scalar( @{ $sites } ), "media/create update media returned" );

    for my $site ( @{ $sites } )
    {
        my $medium = $db->query( "select * from media where name = ?", $site->{ name } )->hash
          || die( "unable to find medium for site $site->{ name }" );
        my $feeds = $db->query( "select * from feeds where media_id = ? order by feeds_id", $medium->{ media_id } )->hashes;
        is( scalar( @{ $feeds } ), 2, "media/create update $site->{ name } num feeds" );

        is( $feeds->[ 0 ]->{ url }, $site->{ feed_url },        "media/create update $site->{ name } default feed url" );
        is( $feeds->[ 1 ]->{ url }, $site->{ custom_feed_url }, "media/create update $site->{ name } custom feed url" );

        for my $feed ( @{ $feeds } )
        {
            is( $feed->{ feed_type },   'syndicated', "$site->{ name } feed type" );
            is( $feed->{ feed_status }, 'active',     "$site->{ name } feed status" );
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
    test_put( '/api/v2/media/update', {}, 1 );

    # test that request with list returns an error
    test_put( '/api/v2/media/update', [ { media_id => 1 } ], 1 );

    my $medium = $db->query( "select * from media where name = ?", $sites->[ 0 ]->{ name } )->hash;

    my $fields = [ qw/media_id name url content_delay editor_notes public_notes foreign_rss_links/ ];

    # test just name change
    my $r = test_put( '/api/v2/media/update', { media_id => $medium->{ media_id }, name => "$medium->{ name } FOO" } );
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

    $r = test_put( '/api/v2/media/update', $medium );
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
    test_post( '/api/v2/media/create', {}, 1 );

    # test that single element without url returns an error
    test_post( '/api/v2/media/create', [ { url => 'http://foo.com' }, { name => "bar" } ], 1 );

    # simple test for creation of url only medium
    my $first_site = $sites->[ 0 ];
    my $r = test_post( '/api/v2/media/create', [ { url => $first_site->{ url } } ] );

    is( scalar( @{ $r } ),     1,                    "media/create url number of statuses" );
    is( $r->[ 0 ]->{ status }, 'new',                "media/create url status" );
    is( $r->[ 0 ]->{ url },    $first_site->{ url }, "media/create url url" );

    my $first_medium = $db->query( "select * from media where name = \$1", $first_site->{ name } )->hash;
    ok( $first_medium, "media/create url found medium with matching title" );

    # test that create reuse the same media source we just created
    $r = test_post( '/api/v2/media/create', [ { url => $first_site->{ url } } ] );
    is( scalar( @{ $r } ),       1,                           "media/create existing number of statuses" );
    is( $r->[ 0 ]->{ status },   'existing',                  "media/create existing status" );
    is( $r->[ 0 ]->{ url },      $first_site->{ url },        "media/create existing url" );
    is( $r->[ 0 ]->{ media_id }, $first_medium->{ media_id }, "media/create existing media_id" );

    # add all media sources in sites, plus one which should return a 404
    my $input = [ map { { url => $_->{ url } } } ( @{ $sites }, { url => 'http://127.0.0.1:123456/456789' } ) ];
    $r = test_post( '/api/v2/media/create', $input );
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

sub test_media($)
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::DB::create_test_story_stack_numerated( $db, $NUM_MEDIA, $NUM_FEEDS_PER_MEDIUM,
        $NUM_STORIES_PER_FEED );

    MediaWords::Test::DB::add_content_to_test_story_stack( $db, $media );

    MediaWords::Test::Solr::setup_test_index( $db );

    MediaWords::Test::API::setup_test_api_key( $db );

    test_media_list( $db, $media );
    test_media_create( $db );
}

sub main
{
    MediaWords::Test::Supervisor::test_with_supervisor( \&test_media,
        [ 'solr_standalone', 'job_broker:rabbitmq', 'rescrape_media' ] );

    done_testing();
}

main();
