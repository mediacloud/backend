use strict;
use warnings;
use Data::Dumper;
use Modern::Perl "2013";

# basic sanity test of crawler functionality

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use Test::More tests => 16;
use Test::Differences;
use Test::Deep;

require Test::NoWarnings;

use MediaWords::Crawler::Engine;
use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::MediaSets;
use MediaWords::DBI::Stories;
use MediaWords::Test::DB;
use MediaWords::Test::Data;
use MediaWords::Test::LocalServer;
use DBIx::Simple::MediaWords;
use MediaWords::StoryVectors;
use LWP::UserAgent;

use Data::Sorting qw( :basics :arrays :extras );
use Readonly;

#use feature 'unicode_strings';

# add a test media source and feed to the database
sub add_test_feed
{
    my ( $db, $url_to_crawl ) = @_;

    Readonly my $sw_data_start_date => '2008-02-03';
    Readonly my $sw_data_end_date   => '2014-02-27';

    my $test_medium = $db->query(
"insert into media (name, url, moderated, feeds_added, sw_data_start_date, sw_data_end_date) values (?, ?, ?, ?, ?, ?) returning *",
        '_ Crawler Test', $url_to_crawl, 0, 0, $sw_data_start_date, $sw_data_end_date
    )->hash;

    ok( MediaWords::StoryVectors::_medium_has_story_words_start_date( $test_medium ) );
    ok( MediaWords::StoryVectors::_medium_has_story_words_end_date( $test_medium ) );

    is( MediaWords::StoryVectors::_get_story_words_start_date_for_medium( $test_medium ), $sw_data_start_date );
    is( MediaWords::StoryVectors::_get_story_words_end_date_for_medium( $test_medium ),   $sw_data_end_date );

    my $feed = $db->query(
        "insert into feeds (media_id, name, url) values (?, ?, ?) returning *",
        $test_medium->{ media_id },
        '_ Crawler Test',
        "$url_to_crawl" . "gv/test.rss"
    )->hash;

    MediaWords::DBI::MediaSets::create_for_medium( $db, $test_medium );

    ok( $feed->{ feeds_id }, "test feed created" );

    return $feed;
}

Readonly my $crawler_timeout => 2 * 60;

# run the crawler for two minutes, which should be enough time to gather all of
# the stories from the test feed and test-extract them
sub run_crawler
{

    my $crawler = MediaWords::Crawler::Engine->new();

    $crawler->processes( 1 );
    $crawler->throttle( 1 );
    $crawler->sleep_interval( 1 );
    $crawler->timeout( $crawler_timeout );
    $crawler->pending_check_interval( 1 );

    $| = 1;

    print "running crawler for one minute ...\n";
    $crawler->crawl();

    print "crawler exiting ...\n";
}

# get stories from database, including content, text, tags, and sentences
sub get_expanded_stories
{
    my ( $db, $feed ) = @_;

    my $stories = $db->query(
        "select s.* from stories s, feeds_stories_map fsm " . "  where s.stories_id = fsm.stories_id and fsm.feeds_id = ?",
        $feed->{ feeds_id } )->hashes;

    for my $story ( @{ $stories } )
    {
        $story->{ content } = ${ MediaWords::DBI::Stories::fetch_content( $db, $story ) };
        $story->{ extracted_text } = MediaWords::DBI::Stories::get_text( $db, $story );
        $story->{ tags } = MediaWords::DBI::Stories::get_db_module_tags( $db, $story, 'NYTTopics' );

        $story->{ story_sentences } =
          $db->query( "select * from story_sentences where stories_id = ? order by stories_id, sentence_number ",
            $story->{ stories_id } )->hashes;
    }

    return $stories;
}

sub _purge_story_sentences_id_field
{
    my ( $sentences ) = @_;

    for my $sentence ( @$sentences )
    {

        $sentence->{ story_sentences_id } = '';
        delete $sentence->{ story_sentences_id };
    }
}

sub _purge_stories_id_field
{
    my ( $sentences ) = @_;

    for my $sentence ( @$sentences )
    {
        $sentence->{ stories_id } = '';
        delete $sentence->{ stories_id };
    }
}

# test various results of the crawler
sub test_stories
{
    my ( $db, $feed ) = @_;

    my $stories = get_expanded_stories( $db, $feed );

    is( @{ $stories }, 1, "story count" );

    my $test_stories =
      MediaWords::Test::Data::stories_arrayref_from_hashref(
        MediaWords::Test::Data::fetch_test_data_from_individual_files( 'crawler_stories/gv' ) );

    my $test_story_hash;
    map { $test_story_hash->{ $_->{ title } } = $_ } @{ $test_stories };

    for my $story ( @{ $stories } )
    {
        my $test_story = $test_story_hash->{ $story->{ title } };
        if ( ok( $test_story, "story match: " . $story->{ title } ) )
        {

            #$story->{ extracted_text } =~ s/\n//g;
            #$test_story->{ extracted_text } =~ s/\n//g;

            for my $field ( qw(publish_date description guid extracted_text) )
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

            is( scalar( @{ $story->{ tags } } ), scalar( @{ $test_story->{ tags } } ), "story tags count" );

            is(
                scalar( @{ $story->{ story_sentences } } ),
                scalar( @{ $test_story->{ story_sentences } } ),
                "story sentence count" . $story->{ stories_id }
            );

            _purge_story_sentences_id_field( $story->{ story_sentences } );
            _purge_story_sentences_id_field( $test_story->{ story_sentences } );

            #HACK so that feedless media doesn't break things.
            _purge_stories_id_field( $story->{ story_sentences } );
            _purge_stories_id_field( $test_story->{ story_sentences } );

            # don't compare timestamp-dependent "db_row_last_updated" fields
            map { delete( $_->{ db_row_last_updated } ) }
              ( @{ $story->{ story_sentences } }, @{ $test_story->{ story_sentences } } );

            cmp_deeply(
                $story->{ story_sentences },
                $test_story->{ story_sentences },
                "story sentences " . $story->{ stories_id }
            );
        }

        delete( $test_story_hash->{ $story->{ title } } );
    }

}

sub get_crawler_data_directory
{
    my $crawler_data_location;

    {
        use FindBin;

        my $bin = $FindBin::Bin;
        say "Bin = '$bin' ";
        $crawler_data_location = "$FindBin::Bin/data/crawler";
    }

    print "crawler data '$crawler_data_location'\n";

    return $crawler_data_location;
}

sub main
{

    my ( $dump ) = @ARGV;

    MediaWords::Test::DB::test_on_test_database(
        sub {
            use Encode;
            my ( $db ) = @_;

            my $crawler_data_location = get_crawler_data_directory();

            my $test_http_server = MediaWords::Test::LocalServer->new( $crawler_data_location );
            $test_http_server->start();
            my $url_to_crawl = $test_http_server->url();

            my $feed = add_test_feed( $db, $url_to_crawl );

            $DB::single = 2;

            my $feed_download = MediaWords::Test::DB::create_download_for_feed( $feed, $db );

            MediaWords::Util::Config::get_config->{ mediawords }->{ extract_in_process } = 1;

            my $crawler = MediaWords::Crawler::Engine->new();

            $crawler->processes( 1 );
            $crawler->throttle( 1 );
            $crawler->sleep_interval( 10 );

            $| = 1;

            $crawler->crawl_single_download( $feed_download->{ downloads_id } );

            print STDERR "download id: $feed_download->{ downloads_id }\n";
            my $content_downloads =
              $db->query( "SELECT * from downloads where  type = 'content' and state <> 'success' and downloads_id > ? ",
                $feed_download->{ downloads_id } )->hashes;

            my $content_download = pop @{ $content_downloads };

            die 'Content downloads is undef.' unless $content_downloads;

            $db->query( " DELETE from stories where stories_id <> ? ", $content_download->{ stories_id } );

            $crawler->crawl_single_download( $content_download->{ downloads_id } );

            if ( defined( $dump ) && ( $dump eq '-d' ) )
            {
                die( "Dumping of stories is only supported within t/test_crawler.t \n" .
                      "test_crawler.t and test_single_crawler_download.t share data" );
            }

            # Wait for a bit for the crawler to finish crawling
            sleep( 10 );

            test_stories( $db, $feed );

            say STDERR "Killing server";
            $test_http_server->stop();

            Test::NoWarnings::had_no_warnings();
        }
    );
}

main();

