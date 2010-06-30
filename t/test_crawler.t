use strict;
use warnings;

# basic sanity test of crawler functionality

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use Test::More;
use Test::Differences;

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
use Perl6::Say;

# add a test media source and feed to the database
sub add_test_feed
{
    my ( $db, $url_to_crawl ) = @_;

    my $test_medium = $db->query(
        "insert into media (name, url, moderated, feeds_added) values (?, ?, ?, ?) returning *",
        '_ Crawler Test',
        $url_to_crawl, 0, 0
    )->hash;
    my $feed = $db->query(
        "insert into feeds (media_id, name, url) values (?, ?, ?) returning *",
        $test_medium->{ media_id },
        '_ Crawler Test',
        "$url_to_crawl" . "gv/test.rss"
    )->hash;

    MediaWords::DBI::MediaSets::create_for_medium($db, $test_medium);

    ok( $feed->{ feeds_id }, "test feed created" );

    return $feed;
}

# run the crawler for one minute, which should be enough time to gather all of the stories from the test feed
sub run_crawler
{

    my $crawler = MediaWords::Crawler::Engine->new();

    $crawler->processes( 1 );
    $crawler->throttle( 1 );
    $crawler->sleep_interval( 1 );
    $crawler->timeout( 60 );
    $crawler->pending_check_interval( 1 );

    $| = 1;

    print "running crawler for one minute ...\n";
    $crawler->crawl();

    print "crawler exiting ...\n";
}

# run extractor, tagger, and vector on all stories
sub process_stories
{
    my ( $db ) = @_;

    print "processing stories ...\n";

    my $stories = $db->query( "select * from stories" )->hashes;

    for my $story ( @{ $stories } )
    {
        my $downloads = $db->query( "select * from downloads where stories_id = ?", $story->{ stories_id } )->hashes;

        foreach my $download ( @{ $downloads } )
        {
            print "extracting text ...\n";
            MediaWords::DBI::DownloadTexts::create_from_download( $db, $download );
        }

        print "adding default tags ...\n";
        MediaWords::DBI::Stories::add_default_tags( $db, $story );

        print "update story_sentence_words ...\n";
        MediaWords::StoryVectors::update_story_sentence_words( $db, $story );
    }

    print "processing stories done.\n";
}

# get stories from database, including content, text, tags, sentences, sentence_words, and story_sentence_words
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

        $story->{ story_sentence_words } =
          $db->query( "select * from story_sentence_words where stories_id = ?", $story->{ stories_id } )->hashes;
    }

    return $stories;
}

# test various results of the crawler
sub test_stories
{
    my ( $db, $feed ) = @_;

    my $stories = get_expanded_stories( $db, $feed );

    is( @{ $stories }, 15, "story count" );

    my $test_stories = MediaWords::Test::Data::fetch_test_data( 'crawler_stories' );

    my $test_story_hash;
    map { $test_story_hash->{ $_->{ title } } = $_ } @{ $test_stories };

    for my $story ( @{ $stories } )
    {
        my $test_story = $test_story_hash->{ $story->{ title } };
        if ( ok( $test_story, "story match: " . $story->{ title } ) )
        {
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
          TODO:
            {
                my $fake_var;    #silence warnings

                my $test_story_sentence_words_count = scalar( @{ $test_story->{ story_sentence_words } } );
                my $story_sentence_words_count      = scalar( @{ $story->{ story_sentence_words } } );

                is( $story_sentence_words_count, $test_story_sentence_words_count, "story words count" );
            }
        }

        delete( $test_story_hash->{ $story->{ title } } );
    }

}

sub test_aggregate_words
{

    my ( $db, $feed ) = @_;

    my ( $start_date ) = $db->query( "select date_trunc( 'day', min(publish_date) ) from stories" )->flat;

    MediaWords::StoryVectors::update_aggregate_words( $db, $start_date );

    ## TODO grab and story the actual top 500 words data.

}

# store the stories as test data to compare against in subsequent runs
sub dump_stories
{
    my ( $db, $feed ) = @_;

    my $stories = get_expanded_stories( $db, $feed );

    MediaWords::Test::Data::store_test_data( 'crawler_stories', $stories );
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

            run_crawler();

            process_stories( $db );

            if ( defined( $dump ) && ( $dump eq '-d' ) )
            {
                dump_stories( $db, $feed );
            }

            test_stories( $db, $feed );

	    test_aggregate_words( $db , $feed );

            print "Killing server\n";
            kill_local_server( $url_to_crawl );

            done_testing();
        }
    );

}

main();

