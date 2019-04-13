use strict;
use warnings;

#
# Basic sanity test of crawler functionality
#
# ---
#
# If you run t/test_feed_download.t with the -d command it rewrites the files. E.g.:
#
#     ./script/run_in_env.sh ./t/test_feed_download.t  -d
#
# This changes the expected results so it's important to make sure that you're
# not masking bugs in the code. Also it's a good idea to manually examine the
# changes in t/data/test_feed_download_stories.pl before committing them.
#

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::More tests => 93;
use Test::Differences;
use Test::Deep;

require Test::NoWarnings;

use MediaWords::DB;
use MediaWords::Crawler::Engine;
use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::Stories;
use MediaWords::Test::Data;
use MediaWords::Test::DB::Create;
use MediaWords::Test::LocalServer;
use MediaWords::Util::DateTime;
use MediaWords::Util::Paths;

use Data::Dumper;
use FindBin;
use Readonly;

# add a test media source and feed to the database
sub add_test_feed
{
    my ( $db, $url_to_crawl ) = @_;

    my $test_medium =
      $db->query( "insert into media (name, url) values (?, ?) returning *", '_ Crawler Test', $url_to_crawl, )->hash;

    my $feed = $db->query(
        "insert into feeds (media_id, name, url) values (?, ?, ?) returning *",
        $test_medium->{ media_id },
        '_ Crawler Test',
        "$url_to_crawl" . "gv/test.rss"
    )->hash;

    ok( $feed->{ feeds_id }, "test feed created" );

    return $feed;
}

# get stories from database, including content, text, tags, and sentences
sub get_expanded_stories
{
    my ( $db, $feed ) = @_;

    my $stories = $db->query(
        "select s.* from stories s, feeds_stories_map fsm " . "  where s.stories_id = fsm.stories_id and fsm.feeds_id = ?",
        $feed->{ feeds_id } )->hashes;

    return $stories;
}

sub _purge_story_sentences_id_field
{
    my ( $sentences ) = @_;

    for my $sentence ( @$sentences )
    {

        #die Dumper ($sentence ) unless $sentence->{story_sentences_id };

        #die Dumper ($sentence);

        $sentence->{ story_sentences_id } = '';
        delete $sentence->{ story_sentences_id };
    }
}

# store the stories as test data to compare against in subsequent runs
sub dump_stories
{
    my ( $db, $feed ) = @_;

    my $stories = get_expanded_stories( $db, $feed );

    my $tz = MediaWords::Util::DateTime::local_timezone()->name;

    map { $_->{ timezone } = $tz } @{ $stories };

    MediaWords::Test::Data::store_test_data( 'test_feed_download_stories', $stories );
}

# test various results of the crawler
sub test_stories
{
    my ( $db, $feed ) = @_;

    my $stories = get_expanded_stories( $db, $feed );

    is( @{ $stories }, 15, "story count" );

    my $test_stories = MediaWords::Test::Data::fetch_test_data( 'test_feed_download_stories' );

    $test_stories = MediaWords::Test::Data::adjust_test_timezone( $test_stories, $test_stories->[ 0 ]->{ timezone } );

    my $test_story_hash;
    map { $test_story_hash->{ $_->{ title } } = $_ } @{ $test_stories };

    for my $story ( @{ $stories } )
    {
        my $test_story = $test_story_hash->{ $story->{ title } };
        if ( ok( $test_story, "story match: " . $story->{ title } ) )
        {

            for my $field ( qw(publish_date description guid) )
            {
                oldstyle_diff;

              TODO:
                {
                    my $fake_var;    #silence warnings
                     #eq_or_diff( $story->{ $field }, encode_utf8($test_story->{ $field }), "story $field match" , {context => 0});
                    is( $story->{ $field }, $test_story->{ $field }, "story $field match" );
                }
            }

            eq_or_diff( $story->{ content }, $test_story->{ content }, "story content matches" );

            #is( scalar( @{ $story->{ tags } } ), scalar( @{ $test_story->{ tags } } ), "story tags count" );

#is ( scalar( @{ $story->{ story_sentences } } ), scalar( @{ $test_story->{ story_sentences } } ), "story sentence count"  . $story->{ stories_id } );

            _purge_story_sentences_id_field( $story->{ story_sentences } );
            _purge_story_sentences_id_field( $test_story->{ story_sentences } );

#cmp_deeply (  $story->{ story_sentences }, $test_story->{ story_sentences } , "story sentences " . $story->{ stories_id } );
        }

        delete( $test_story_hash->{ $story->{ title } } );
    }

}

sub main
{

    my ( $dump ) = @ARGV;

    # Errors might want to print out UTF-8 characters
    binmode( STDERR, ':utf8' );
    binmode( STDOUT, ':utf8' );
    my $builder = Test::More->builder;

    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    my $db = MediaWords::DB::connect_to_db();

    my $crawler_data_location = "/t/data/crawler/";

    my $test_http_server = MediaWords::Test::LocalServer->new( $crawler_data_location );
    $test_http_server->start();
    my $url_to_crawl = $test_http_server->url();

    my $feed = add_test_feed( $db, $url_to_crawl );

    my $download = MediaWords::Test::DB::Create::create_download_for_feed( $db, $feed );

    my $crawler = MediaWords::Crawler::Engine->new();
    $crawler->fetcher_number( 1 );

    INFO "starting fetch_and_handle_single_download";

    $crawler->fetch_and_handle_single_download( $download );

    my $redundant_feed_download = MediaWords::Test::DB::Create::create_download_for_feed( $db, $feed );

    $crawler->fetch_and_handle_single_download( $redundant_feed_download );

    if ( defined( $dump ) && ( $dump eq '-d' ) )
    {
        dump_stories( $db, $feed );
    }

    test_stories( $db, $feed );

    INFO "Killing server";
    $test_http_server->stop();

    Test::NoWarnings::had_no_warnings();
}

main();
