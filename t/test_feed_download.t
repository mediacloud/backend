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

use Test::More;
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

# get stories from database, including content, text, tags, sentences, sentence_words, and story_sentence_words
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

    MediaWords::Test::Data::store_test_data( 'test_feed_download_stories', $stories );
}

# test various results of the crawler
sub test_stories
{
    my ( $db, $feed ) = @_;

    my $stories = get_expanded_stories( $db, $feed );

    is( @{ $stories }, 15, "story count" );

    my $test_stories = MediaWords::Test::Data::fetch_test_data( 'test_feed_download_stories' );

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

            #is( scalar( @{ $story->{ tags } } ), scalar( @{ $test_story->{ tags } } ), "story tags count" );

#is ( scalar( @{ $story->{ story_sentences } } ), scalar( @{ $test_story->{ story_sentences } } ), "story sentence count"  . $story->{ stories_id } );

            _purge_story_sentences_id_field( $story->{ story_sentences } );
            _purge_story_sentences_id_field( $test_story->{ story_sentences } );

#cmp_deeply (  $story->{ story_sentences }, $test_story->{ story_sentences } , "story sentences " . $story->{ stories_id } );

          TODO:
            {
                my $fake_var;    #silence warnings

                #my $test_story_sentence_words_count = scalar( @{ $test_story->{ story_sentence_words } } );
                #my $story_sentence_words_count      = scalar( @{ $story->{ story_sentence_words } } );

    #is( $story_sentence_words_count, $test_story_sentence_words_count, "story words count for "  . $story->{ stories_id } );
            }
        }

        delete( $test_story_hash->{ $story->{ title } } );
    }

}

sub kill_local_server
{
    my ( $server_url ) = @_;

    my $ua = LWP::UserAgent->new;

    $ua->timeout( 10 );

    my $kill_url = "$server_url" . "kill_server";
    print STDERR "Getting $kill_url\n";
    my $resp = $ua->get( $kill_url ) || die;
    print STDERR "got url";
    die $resp->status_line unless $resp->is_success;
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

            my $url_to_crawl = MediaWords::Test::LocalServer::start_server( $crawler_data_location );

            my $feed = add_test_feed( $db, $url_to_crawl );

            my $download = MediaWords::Test::DB::create_download_for_feed( $feed, $db );

            my $crawler = MediaWords::Crawler::Engine::_create_fetcher_engine_for_testing( 1 );

            say STDERR "starting fetch_and_handle_single_download";

            $crawler->fetch_and_handle_single_download( $download );

            my $redundant_feed_download = MediaWords::Test::DB::create_download_for_feed( $feed, $db );

            $crawler->fetch_and_handle_single_download( $redundant_feed_download );

            if ( defined( $dump ) && ( $dump eq '-d' ) )
            {
                dump_stories( $db, $feed );
            }

            test_stories( $db, $feed );

            # print "Killing server\n";

            kill_local_server( $url_to_crawl );

            Test::NoWarnings::had_no_warnings();
            done_testing();
        }
    );

}

main();

