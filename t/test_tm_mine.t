#!/usr/bin/env perl

package t::test_tm_mine;

use strict;
use warnings;

# basic intergration test for topic mapper's spider

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use English '-no_match_vars';

use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use MediaWords::Test::HashServer;
use Readonly;
use Test::More;
use Text::Lorem::More;

use MediaWords::Job::TM::MineTopic;
use MediaWords::TM::Mine;
use MediaWords::Test::DB;
use MediaWords::Test::Supervisor;
use MediaWords::Util::Config;
use MediaWords::Util::SQL;
use MediaWords::Util::Web;

Readonly my $BASE_PORT => 8890;

Readonly my $NUM_SITES          => 5;
Readonly my $NUM_PAGES_PER_SITE => 10;
Readonly my $NUM_LINKS_PER_PAGE => 2;

Readonly my $TOPIC_PATTERN => 'FOOBARBAZ';

sub get_html_link
{
    my ( $page ) = @_;

    my $lorem = Text::Lorem::More->new();

    if ( 0 && int( rand( 3 ) ) )
    {
        return "<a href='$page->{ url }'>" . $lorem->words( 2 ) . "</a>";
    }
    else
    {
        return $page->{ url };
    }
}

sub generate_content_for_site
{
    my ( $site ) = @_;

    my $lorem = Text::Lorem::More->new();

    my $body = $lorem->sentences( 5 );

    return <<HTML;
<html>
<head>
    <title>$site->{ title }</title>
</head>
<body>
    <p>
    $body
    </p>
</body>
</html>
HTML
}

sub generate_content_for_page
{
    my ( $site, $page ) = @_;

    my $lorem = Text::Lorem::More->new();

    my $num_links      = scalar( @{ $page->{ links } } );
    my $num_paragraphs = int( rand( 10 ) + 3 ) + $num_links;

    my $paragraphs = [];

    for my $i ( 0 .. $num_paragraphs - 1 )
    {
        my $text = $lorem->sentences( 5 );
        if ( $i < $num_links )
        {
            my $html_link = get_html_link( $page->{ links }->[ $i ] );
            $text .= " $html_link";
        }

        push( @{ $paragraphs }, $text );
    }

    if ( rand( 2 ) < 1 )
    {
        push( @{ $paragraphs }, $lorem->words( 10 ) . " $TOPIC_PATTERN" );
        $page->{ matches_topic } = 1;
    }

    my $dead_link_text = $lorem->sentences( 5 );
    $dead_link_text .= " <a href='$page->{ url }/dead'>dead link</a>";

    push( @{ $paragraphs }, $dead_link_text );

    my $body = join( "\n\n", map { "<p>\n$_\n</p>" } @{ $paragraphs } );

    return <<HTML;
<html>
<head>
    <title>$page->{ title }</title>
</head>
<body>
    $body
</body>
</html>
HTML

}

sub generate_content_for_sites
{
    my ( $sites ) = @_;

    for my $site ( @{ $sites } )
    {
        $site->{ content } = generate_content_for_site( $site );

        for my $page ( @{ $site->{ pages } } )
        {
            $page->{ content } = generate_content_for_page( $site, $page );
        }
    }
}

# generate test set of sites
sub get_test_sites()
{
    my $sites = [];
    my $pages = [];

    # my $base_port = $BASE_PORT + int( rand( 200 ) );
    my $base_port = $BASE_PORT;

    for my $site_id ( 0 .. $NUM_SITES - 1 )
    {
        my $port = $base_port + $site_id;

        my $site = {
            port  => $port,
            id    => $site_id,
            url   => "http://127.0.0.1:$port/",
            title => "site $site_id"
        };

        my $num_pages = int( rand( $NUM_PAGES_PER_SITE ) ) + 1;
        for my $page_id ( 0 .. $num_pages - 1 )
        {
            my $date = MediaWords::Util::SQL::get_sql_date_from_epoch( time() - ( rand( 365 ) * 86400 ) );

            my $path = "page-$page_id";

            my $page = {
                id          => $page_id,
                path        => "/$path",
                url         => "$site->{ url }$path",
                title       => "page $page_id",
                pubish_date => $date,
                links       => []
            };

            push( @{ $pages },           $page );
            push( @{ $site->{ pages } }, $page );
        }

        push( @{ $sites }, $site );
    }

    my $all_pages = [];
    map { push( @{ $all_pages }, @{ $_->{ pages } } ) } @{ $sites };
    for my $page ( @{ $all_pages } )
    {
        my $num_links = int( rand( $NUM_LINKS_PER_PAGE ) );
        for my $link_id ( 0 .. $num_links - 1 )
        {
            my $linked_page_id = int( rand( scalar( @{ $all_pages } ) ) );
            my $linked_page    = $all_pages->[ $linked_page_id ];

            unless ( MediaWords::Util::URL::urls_are_equal( $page->{ url }, $linked_page->{ url } ) )
            {
                push( @{ $page->{ links } }, $linked_page );
            }
        }
    }

    generate_content_for_sites( $sites );

    return $sites;
}

# add a medium for each site so that the topic mapper's spider can find the medium that corresponds to each url
sub add_site_media
{
    my ( $db, $sites ) = @_;

    for my $site ( @{ $sites } )
    {
        $site->{ medium } = $db->create(
            'media',
            {
                url  => $site->{ url },
                name => $site->{ title },
            }
        );
    }
}

sub start_hash_servers
{
    my ( $sites ) = @_;

    my $hash_servers = [];

    for my $site ( @{ $sites } )
    {
        my $site_hash = {};

        $site_hash->{ '/' } = $site->{ content };

        map { $site_hash->{ $_->{ path } } = $_->{ content } } @{ $site->{ pages } };

        my $hs = MediaWords::Test::HashServer->new( $site->{ port }, $site_hash );

        DEBUG "starting hash server $site->{ id }";

        $hs->start();

        push( @{ $hash_servers }, $hs );
    }

    # wait for the hash servers to start
    sleep( 1 );

    return $hash_servers;
}

sub test_page
{
    my ( $label, $url, $expected_content ) = @_;

    TRACE "test page: $label $url";

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $request  = MediaWords::Util::Web::UserAgent::Request->new( 'GET', $url );
    my $response = $ua->request( $request );

    ok( $response->is_success, "request success: $label $url" );

    my $got_content = $response->decoded_content;

    TRACE "got content";

    is( $got_content, $expected_content, "simple page test: $label" );
}

sub test_pages
{
    my ( $sites ) = @_;

    for my $site ( @{ $sites } )
    {
        DEBUG "testing pages for site $site->{ id }";
        test_page( "site $site->{ id }", $site->{ url }, $site->{ content } );

        map { test_page( "page $site->{ id } $_->{ id }", $_->{ url }, $_->{ content } ) } @{ $site->{ pages } };
    }
}

sub seed_unlinked_urls
{
    my ( $db, $topic, $sites ) = @_;

    my $all_pages = [];
    map { push( @{ $all_pages }, @{ $_->{ pages } } ) } @{ $sites };

    # do not seed urls that are linked directly from a page that is a topic match.
    # this forces the test to succesfully discover those pages through spidering.
    my $non_seeded_url_lookup = {};
    for my $page ( @{ $all_pages } )
    {
        if ( $page->{ matches_topic } )
        {
            map { $non_seeded_url_lookup->{ $_->{ url } } = 1 } @{ $page->{ links } };
        }
    }

    my $seed_pages = [];
    for my $page ( @{ $all_pages } )
    {
        if ( $non_seeded_url_lookup->{ $page->{ url } } )
        {
            DEBUG( "non seeded url: $page->{ url }" );
        }
        else
        {
            DEBUG( "seed url: $page->{ url }" );
            push( @{ $seed_pages }, $page );
        }
    }

    for my $seed_page ( @{ $all_pages } )
    {
        $db->create(
            'topic_seed_urls',
            {
                topics_id => $topic->{ topics_id },
                url       => $seed_page->{ url }
            }
        );
    }
}

sub create_topic
{
    my ( $db, $sites ) = @_;

    my $now        = MediaWords::Util::SQL::sql_now();
    my $start_date = MediaWords::Util::SQL::increment_day( $now, -30 );
    my $end_date   = MediaWords::Util::SQL::increment_day( $now, 30 );

    my $topic = $db->create(
        'topics',
        {
            name                => 'test topic',
            description         => 'test topic',
            pattern             => $TOPIC_PATTERN,
            solr_seed_query     => 'stories_id:0',
            solr_seed_query_run => 't',
            start_date          => $start_date,
            end_date            => $end_date,
            job_queue           => 'mc',
            max_stories         => 100_000,

        }
    );

    seed_unlinked_urls( $db, $topic, $sites );

    # avoid race condition in TM::Mine
    $db->create( 'tag_sets', { name => 'extractor_version' } );

    return $topic;
}

sub test_topic_stories
{
    my ( $db, $topic, $sites ) = @_;

    my $topic_stories = $db->query( <<SQL, $topic->{ topics_id } )->hashes;
select cs.*, s.*
    from topic_stories cs
        join stories s on ( s.stories_id = cs.stories_id )
    where cs.topics_id = ?
SQL

    my $all_pages = [];
    map { push( @{ $all_pages }, @{ $_->{ pages } } ) } @{ $sites };

    DEBUG "ALL PAGES: " . scalar( @{ $all_pages } );

    my $topic_pages = [ grep { $_->{ matches_topic } } @{ $all_pages } ];

    DEBUG "TOPIC PAGES: " . scalar( @{ $topic_pages } );

    my $topic_pages_lookup = {};
    map { $topic_pages_lookup->{ $_->{ url } } = $_ } @{ $topic_stories };

    for my $topic_story ( @{ $topic_stories } )
    {
        ok( $topic_pages_lookup->{ $topic_story->{ url } }, "topic story found for topic page '$topic_story->{ url }'" );

        delete( $topic_pages_lookup->{ $topic_story->{ url } } );
    }

    is( scalar( keys( %{ $topic_pages_lookup } ) ),
        0, "missing topic story for topic pages: " . Dumper( values( %{ $topic_pages_lookup } ) ) );

    my ( $dead_link_count ) = $db->query( "select count(*) from topic_fetch_urls where state ='request failed'" )->flat;
    is( $dead_link_count, scalar( @{ $topic_pages } ), "dead link count" );

    if ( $dead_link_count != scalar( @{ $topic_pages } ) )
    {
        my $fetch_states = $db->query( "select count(*), state from topic_fetch_urls group by state" )->hashes();
        WARN( "fetch states: " . Dumper( $fetch_states ) );

        my $fetch_errors = $db->query( "select * from topic_fetch_urls where state = 'python error'" )->hashes();
        WARN( "fetch errors: " . Dumper( $fetch_errors ) );
    }
}

sub test_topic_links
{
    my ( $db, $topic, $sites ) = @_;

    my $cid = $topic->{ topics_id };

    my $cl = $db->query( "select * from topic_links" )->hashes;

    TRACE "topic links: " . Dumper( $cl );

    my $all_pages = [];
    map { push( @{ $all_pages }, @{ $_->{ pages } } ) } @{ $sites };

    for my $page ( @{ $all_pages } )
    {
        next if ( !$page->{ matches_topic } );

        for my $link ( @{ $page->{ links } } )
        {
            next unless ( $link->{ matches_topic } );

            my $topic_links = $db->query( <<SQL, $page->{ url }, $link->{ url }, $cid )->hashes;
select *
    from topic_links cl
        join stories s on ( cl.stories_id = s.stories_id )
    where
        s.url = \$1 and
        cl.url = \$2 and
        cl.topics_id = \$3
SQL

            is( scalar( @{ $topic_links } ), 1, "number of topic_links for $page->{ url } -> $link->{ url }" );
        }
    }

    my $topic_spider_metric = $db->query( <<SQL, $topic->{ topics_id } )->hash;
select sum( links_processed ) links_processed from topic_spider_metrics where topics_id = ?
SQL

    ok( $topic_spider_metric,                                           "topic spider metrics exist" );
    ok( $topic_spider_metric->{ links_processed } > scalar( @{ $cl } ), "metrics links_processed greater than topic_links" );
}

# test that no errors exist in the topics or snapshots tables
sub test_for_errors
{
    my ( $db ) = @_;

    my $error_topics = $db->query( "select * from topics where state = 'error'" )->hashes;

    ok( scalar( @{ $error_topics } ) == 0, "topic errors: " . Dumper( $error_topics ) );

    my $error_snapshots = $db->query( "select * from snapshots where state = 'error'" )->hashes;

    ok( scalar( @{ $error_snapshots } ) == 0, "snapshot errors: " . Dumper( $error_snapshots ) );
}

sub test_spider_results
{
    my ( $db, $topic, $sites ) = @_;

    test_topic_stories( $db, $topic, $sites );

    test_topic_links( $db, $topic, $sites );

    test_for_errors( $db );
}

sub get_site_structure
{
    my ( $sites ) = @_;

    my $meta_sites = [];
    for my $site ( @{ $sites } )
    {
        my $meta_site = { url => $site->{ url } };
        for my $page ( @{ $site->{ pages } } )
        {
            my $meta_page = { url => $page->{ url }, matches_topic => $page->{ matches_topic } };
            map { push( @{ $meta_page->{ links } }, $_->{ url } ) } @{ $page->{ links } };

            $meta_page->{ content } = $page->{ content }
              if ( $page->{ matches_topic } && $page->{ matches_topic } );

            push( @{ $meta_site->{ pages } }, $meta_page );
        }

        push( @{ $meta_sites }, $meta_site );
    }

    return $meta_sites;
}

# test that MediaWords::TM::Mine::get_full_solr_query returns the expected query
sub test_full_solr_query($)
{
    my ( $db ) = @_;

    WARN( "BEGIN test_full_solr_query" );

    MediaWords::Test::DB::Create::create_test_story_stack_numerated( $db, 10, 2, 2 );

    # just need some randomly named tags, so copying media names works as well as anything
    $db->query( "insert into tag_sets( name ) values ('foo' )" );

    $db->query( "insert into tags ( tag, tag_sets_id ) select media.name, tag_sets_id from media, tag_sets" );

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, 'full solr query' );
    my $topics_id = $topic->{ topics_id };

    $db->query( "insert into topics_media_map ( topics_id, media_id ) select ?, media_id from media limit 5",   $topics_id );
    $db->query( "insert into topics_media_tags_map ( topics_id, tags_id ) select ?, tags_id from tags limit 5", $topics_id );

    my $got_full_solr_query = MediaWords::TM::Mine::get_full_solr_query( $db, $topic );

    my @q_matches =
      $got_full_solr_query->{ q } =~ /\( (.*) \) and \( media_id:\( ([\d\s]+) \) or tags_id_media:\( ([\d\s]+) \) \)/;
    ok( @q_matches, "full solr query: q matches expected pattern: $got_full_solr_query->{ q }" );
    my ( $query, $media_ids_list, $tags_ids_list ) = @q_matches;

    my @fq_matches = $got_full_solr_query->{ fq } =~
      /publish_day\:\[(\d\d\d\d\-\d\d\-\d\d)T00:00:00Z TO (\d\d\d\d\-\d\d\-\d\d)T23:59:59Z\]/;
    ok( @fq_matches, "full solr query: fq matches expected pattern: $got_full_solr_query->{ fq }" );
    my ( $start_date, $end_date ) = @fq_matches;

    is( $topic->{ solr_seed_query }, $query, "full solr query: solr_seed_query" );

    is( $topic->{ start_date }, $start_date, "full solr query: start_date" );

    my $tp_start = Time::Piece->strptime( $topic->{ start_date }, '%Y-%m-%d' );
    my $expected_end_date = $tp_start->add_months( 1 )->strftime( '%Y-%m-%d' );
    is( $end_date, $expected_end_date, "full solr query: end_date" );

    my $got_media_ids_list = join( ',', sort( split( ' ', $media_ids_list ) ) );
    my $expected_media_ids = $db->query( "select media_id from topics_media_map where topics_id = ?", $topics_id )->flat;
    my $expected_media_ids_list = join( ',', sort( @{ $expected_media_ids } ) );
    is( $got_media_ids_list, $expected_media_ids_list, "full solr query: media ids" );

    my $got_tags_ids_list = join( ',', sort( split( ' ', $tags_ids_list ) ) );
    my $expected_tags_ids = $db->query( "select tags_id from topics_media_tags_map where topics_id = ?", $topics_id )->flat;
    my $expected_tags_ids_list = join( ',', sort( @{ $expected_tags_ids } ) );
    is( $got_tags_ids_list, $expected_tags_ids_list, "full solr query: media ids" );

    my $offset_full_solr_query = MediaWords::TM::Mine::get_full_solr_query( $db, $topic, undef, undef, 1 );
    @fq_matches = $offset_full_solr_query->{ fq } =~
      /publish_day\:\[(\d\d\d\d\-\d\d\-\d\d)T00:00:00Z TO (\d\d\d\d\-\d\d\-\d\d)T23:59:59Z\]/;

    ok( @fq_matches, "offset solr query:  matches expected pattern: $got_full_solr_query->{ fq }" );

    my ( $offset_start_date, $offset_end_date ) = @fq_matches;

    $tp_start = Time::Piece->strptime( $topic->{ start_date }, '%Y-%m-%d' )->add_months( 1 );
    my $expected_start_date = $tp_start->strftime( '%Y-%m-%d' );
    is( $offset_start_date, $expected_start_date, "offset solr query: start_date" );

    $expected_end_date = $tp_start->add_months( 1 )->strftime( '%Y-%m-%d' );
    is( $offset_end_date, $expected_end_date, "offset solr query: end_date" );

    my $undef_full_solr_query = MediaWords::TM::Mine::get_full_solr_query( $db, $topic, undef, undef, 3 );
    ok( !$undef_full_solr_query, "solr query offset beyond end date is undef" );
}

sub test_spider
{
    my ( $db ) = @_;

    # we pseudo-randomly generate test data, but we want repeatable tests
    srand( 3 );

    MediaWords::Util::Mail::enable_test_mode();

    my $sites = get_test_sites();

    TRACE "SITE STRUCTURE " . Dumper( get_site_structure( $sites ) );

    add_site_media( $db, $sites );

    my $hash_servers = start_hash_servers( $sites );

    test_pages( $sites );

    my $topic = create_topic( $db, $sites );

    # topic date modeling confuses perl TAP for some reason
    MediaWords::Util::Config::get_config()->{ mediawords }->{ topic_model_reps } = 0;

    my $mine_args = {
        topics_id                       => $topic->{ topics_id },
        skip_post_processing            => 1,                       #
        cache_broken_downloads          => 0,                       #
        import_only                     => 0,                       #
        skip_outgoing_foreign_rss_links => 0,                       #
        test_mode                       => 1
    };

    MediaWords::Job::TM::MineTopic->run_locally( $mine_args );

    # MediaWords::TM::Mine::mine_topic( $db, $topic, $mine_options );

    test_spider_results( $db, $topic, $sites );

    map { $_->stop } @{ $hash_servers };

    done_testing();
}

sub run_nonspider_tests($)
{
    my ( $db ) = @_;

    test_full_solr_query( $db );
}

sub main
{
    MediaWords::Test::DB::test_on_test_database( \&run_nonspider_tests );
    MediaWords::Test::Supervisor::test_with_supervisor( \&test_spider,
        [ 'job_broker:rabbitmq', 'extract_story_links', 'fetch_link' ] );
}

main();
