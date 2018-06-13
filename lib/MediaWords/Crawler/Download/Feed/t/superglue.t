#!/usr/bin/perl
#
# Test MediaWords::Crawler::Download::Feed::Superglue feed
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::Crawler::Download::Feed::Superglue;

use Readonly;

use Test::NoWarnings;
use Test::More;
use Test::Deep;

use MediaWords::DB;
use MediaWords::Test::DB;
use MediaWords::Crawler::Engine;
use MediaWords::Test::HTTP::HashServer;

sub test_fetch_handle_download($$)
{
    my ( $db, $superglue_url ) = @_;

    my $medium = $db->create(
        'media',
        {
            name => "Media for test feed $superglue_url",
            url  => 'http://www.example.com/',
        }
    );

    my $feed = $db->create(
        'feeds',
        {
            name     => 'feed',
            type     => 'superglue',
            url      => $superglue_url,
            media_id => $medium->{ media_id }
        }
    );

    my $download = MediaWords::Test::DB::create_download_for_feed( $db, $feed );

    my $handler = MediaWords::Crawler::Engine::handler_for_download( $db, $download );

    my $response = $handler->fetch_download( $db, $download );
    $handler->handle_response( $db, $download, $response );

    $download = $db->find_by_id( 'downloads', $download->{ downloads_id } );
    is( $download->{ state }, 'success', "Download's state is not 'success': " . $download->{ state } );
    ok( !$download->{ error_message }, "Download's error_message should be empty: " . $download->{ error_message } );

    # We don't know how many stories will be in remote test feed and how will
    # they look like, so we just query for stories with bad patterns
    my $non_superglue_feed_count = $db->query( "SELECT COUNT(*) FROM feeds WHERE type != 'superglue'" )->flat->[ 0 ] + 0;
    ok( $non_superglue_feed_count == 0, "All feeds must be 'superglue'" );

    my $story_count = $db->query( 'SELECT COUNT(*) FROM stories' )->flat->[ 0 ] + 0;
    ok( $story_count > 0, "Some stories must have been found in 'superglue' feed" );

    my $story_sentence_count = $db->query( 'SELECT COUNT(*) FROM story_sentences' )->flat->[ 0 ] + 0;
    ok( $story_sentence_count > 0, "Some sentences must have been extracted from 'superglue' feed" );

    my $metadata_count = $db->query( 'SELECT COUNT(*) FROM stories_superglue_metadata' )->flat->[ 0 ] + 0;
    ok( $metadata_count == $story_count, 'Superglue metadata count should match story count' );

    my $bad_stories = $db->query(
        <<SQL
        SELECT *
        FROM stories
        WHERE media_id IS NULL
           OR media_id = 0
           OR url IS NULL
           OR url = ''
           OR url ILIKE 'http%'     -- Expect URL to look like GUID
           OR guid IS NULL
           OR guid = ''
           OR guid ILIKE 'http%'    -- Expect GUID to not look like URL in order to not leak private data
           OR guid != url           -- Instead of URL, we store GUID to hide the video URL
           OR title IS NULL
           OR title = ''
           OR description IS NULL
           OR description = ''
           OR full_text_rss = 'f'
SQL
    )->hashes;
    ok( scalar( @{ $bad_stories } ) == 0, "Some stories matched the 'bad stories' query: " . Dumper( $bad_stories ) );

    my $bad_metadata = $db->query(
        <<SQL
        SELECT *
        FROM stories_superglue_metadata
        WHERE NOT EXISTS (
            SELECT 1
            FROM stories
            WHERE stories_superglue_metadata.stories_id = stories_superglue_metadata.stories_id
        )
           OR segment_duration IS NULL
           OR segment_duration < 0
           OR video_url IS NULL
           OR video_url = ''
           OR video_url NOT ILIKE 'http%'
           OR thumbnail_url IS NULL
           OR (thumbnail_url != '' AND thumbnail_url NOT ILIKE 'http%')
SQL
    )->hashes;
    ok( scalar( @{ $bad_metadata } ) == 0, "Some metadata matched the 'bad metadata' query: " . Dumper( $bad_metadata ) );

    # Try running handle_response() with the same feed data again, see if if_new() works
    $handler->handle_response( $db, $download, $response );

    my $story_count_after_handling_duplicates = $db->query( 'SELECT COUNT(*) FROM stories' )->flat->[ 0 ] + 0;
    ok( $story_count_after_handling_duplicates == $story_count, "Duplicate stories got into 'stories' table" );
}

sub test_superglue($)
{
    my ( $superglue_url ) = @_;

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my $db = shift;

            test_fetch_handle_download( $db, $superglue_url );
            Test::NoWarnings::had_no_warnings();
        }
    );
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    Readonly my $TEST_HTTP_SERVER_PORT => 9998;
    Readonly my $TEST_HTTP_SERVER_URL  => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;
    my $local_superglue_url = $TEST_HTTP_SERVER_URL . '/feed';

    my $remote_superglue_url = $ENV{ MC_SUPERGLUE_TEST_URL };

    if ( $remote_superglue_url )
    {
        plan tests => 21;
    }
    else
    {
        plan tests => 11;
    }

    say STDERR "Testing against local Superglue test HTTP server...";
    my $pages = {

        '/feed' => <<XML,
<?xml version='1.0' encoding='UTF-8'?>
<rss xmlns:atom="http://www.w3.org/2005/Atom"
     xmlns:content="http://purl.org/rss/1.0/modules/content/"
     xmlns:segment="https://github.com/Viral-MediaLab/superglue-rss"
     version="2.0">
    <channel>
        <title>Test Superglue feed</title>
        <link>http://www.example.com/</link>
        <description>Test Superglue feed</description>
        <docs>http://www.rssboard.org/rss-specification</docs>
        <generator>python-feedgen</generator>
        <lastBuildDate>Thu, 10 Nov 2016 14:42:22 +0000</lastBuildDate>
        <item>
            <title>First show</title>
            <link>http://www.example.com/first_show.mp4#t=0.00,1018.00</link>
            <description>LOREM IPSUM DOLOR SIT AMET, CONSECTETUR ADIPISCING ELIT. &gt;&gt;
MAURIS CONSECTETUR EST AT ALIQUET SAGITTIS. DONEC NISI SAPIEN,
FAUCIBUS EU DOLOR A, CONVALLIS SEMPER EX. PELLENTESQUE MOLESTIE, LOREM
ET PHARETRA PORTA, LIBERO QUAM FEUGIAT NIBH, EGET ULTRICIES LEO LEO UT
ODIO. DONEC ID ANTE IN RISUS EGESTAS PLACERAT SIT AMET NON SAPIEN.
ALIQUAM EGET ANTE ET LACUS SAGITTIS TRISTIQUE AC VITAE ORCI. &gt;&gt;
INTEGER ID PHARETRA QUAM. INTEGER FACILISIS, ERAT EU SUSCIPIT
CONVALLIS, LECTUS NEQUE VESTIBULUM METUS, QUIS BIBENDUM NISL LEO AT
SAPIEN. DONEC IN TELLUS TINCIDUNT METUS FRINGILLA TINCIDUNT. AENEAN
PELLENTESQUE QUAM AT URNA EUISMOD, AT ELEIFEND LECTUS CURSUS. DONEC
ELIT LECTUS, RUTRUM ET ARCU NON, SCELERISQUE TINCIDUNT MAGNA. VIVAMUS
SIT AMET LEO CONVALLIS, FINIBUS LIGULA -- &gt;&gt; QUIS, MALESUADA
METUS. FUSCE COMMODO PRETIUM LIGULA, EU ULTRICES DIAM PULVINAR ID.
DONEC SCELERISQUE EGESTAS DUI, NON CONSEQUAT METUS SODALES AC. DUIS IN
URNA DUI. VESTIBULUM VEL CONDIMENTUM ODIO, NEC VENENATIS TELLUS.
ALIQUAM VULPUTATE SAGITTIS AUGUE UT PRETIUM.</description>
            <guid isPermaLink="false">5824777cca50550006203b2f_0</guid>
            <enclosure url="http://www.example.com/first_show.jpg" length="0" type="image/jpeg"/>
            <pubDate>Thu, 10 Nov 2016 13:34:52 +0000</pubDate>
            <segment:duration>1018.004</segment:duration>
        </item>
        <item>
            <title>First show (cont.)</title>
            <link>http://www.example.com/first_show.mp4#t=1021.29,1490.29</link>
            <description>&gt;&gt;&gt; LOREM IPSUM DOLOR SIT AMET, CONSECTETUR ADIPISCING ELIT. MORBI
VESTIBULUM, LOREM EU EUISMOD CONSEQUAT, EROS QUAM PULVINAR ARCU, SIT
AMET LAOREET FELIS DUI ET MI. -- &gt;&gt; PRAESENT INTERDUM VESTIBULUM
EROS, CONVALLIS SAGITTIS ERAT. CRAS ARCU ANTE, LACINIA A TORTOR VEL,
BLANDIT FERMENTUM ENIM. VESTIBULUM EGET ORCI VITAE MAURIS LACINIA
EFFICITUR SED SIT AMET VELIT. SED AC LECTUS EGET ERAT MOLESTIE
FERMENTUM VEL SED ARCU. &gt;&gt; NUNC ODIO ANTE, LACINIA IN ENIM A,
PULVINAR ELEMENTUM PURUS. PRAESENT ULLAMCORPER TORTOR ENIM, AC
SCELERISQUE ERAT CONSECTETUR NON. ETIAM TEMPUS, DUI SIT AMET
VESTIBULUM RUTRUM, EROS METUS TEMPOR NISI, TEMPOR ALIQUET NULLA LIBERO
ID LOREM. SED FERMENTUM SAPIEN UT LEO VESTIBULUM, EU EFFICITUR NIBH
EFFICITUR. &gt;&gt; DUIS EFFICITUR VOLUTPAT MAGNA. DONEC METUS LACUS,
INTERDUM LUCTUS DIAM ID, ULLAMCORPER VENENATIS NISL. INTERDUM ET
MALESUADA FAMES AC ANTE IPSUM PRIMIS IN FAUCIBUS. NULLA NULLA TURPIS,
FAUCIBUS IN PULVINAR EU, COMMODO IN NISI. FUSCE RHONCUS, JUSTO NON
MALESUADA RHONCUS, METUS NISL PULVINAR LIGULA, NON ORNARE ORCI LEO
EGET NEQUE. -- &gt;&gt; ALIQUAM UT LECTUS INTERDUM, PELLENTESQUE EX
BIBENDUM, LACINIA TORTOR.</description>
            <guid isPermaLink="false">5824777cca50550006203b2f_2</guid>
            <enclosure url="http://www.example.com/first_show.jpg" length="0" type="image/jpeg"/>
            <pubDate>Thu, 10 Nov 2016 13:34:52 +0000</pubDate>
            <segment:duration>468.997</segment:duration>
        </item>
    </channel>
</rss>
XML
    };

    my $hs = MediaWords::Test::HTTP::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );
    $hs->start();

    test_superglue( $local_superglue_url );

    $hs->stop();

    if ( $remote_superglue_url )
    {
        say STDERR "Testing against remote (live) Superglue HTTP server...";
        test_superglue( $remote_superglue_url );
    }
}

main();
