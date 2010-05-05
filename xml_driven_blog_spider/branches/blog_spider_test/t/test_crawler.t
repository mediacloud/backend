use strict;

# basic sanity test of crawler functionality

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use Test::More qw( no_plan );

use MediaWords::Crawler::Engine;
use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::Stories;
use MediaWords::Test::DB;
use MediaWords::Test::Data;
use DBIx::Simple::MediaWords;

# add a test media source and feed to the database
sub add_test_feed
{
    my ( $db ) = @_;

    my $test_medium = $db->query( "insert into media (name, url) values (?, ?) returning *", 
                                  '_ Crawler Test', 'http://admin.mediacloud.org/files/test/crawler/' )->hash;
    my $feed = $db->query( "insert into feeds (media_id, name, url) values (?, ?, ?) returning *",
                           $test_medium->{ media_id }, '_ Crawler Test',
                           'http://admin.mediacloud.org/files/test/crawler/gv/test.rss' )->hash;
                                
    ok( $feed->{ feeds_id } , "test feed created" );

    return $feed;
}

# run the crawler for one minute, which should be enough time to gather all of the stories from the test feed
sub run_crawler
{
        
    my $crawler = MediaWords::Crawler::Engine->new();

    $crawler->processes(2);
    $crawler->throttle(1);
    $crawler->sleep_interval(1);
    $crawler->timeout(60);
    $crawler->pending_check_interval(1);

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
        my $download = $db->query( "select * from downloads where stories_id = ?", $story->{ stories_id } )->hash;
        
        print "extracting text ...\n";
        MediaWords::DBI::DownloadTexts::create_from_download( $db, $download );
        
        print "adding default tags ...\n";
        MediaWords::DBI::Stories::add_default_tags( $db, $story );
        
        print "add vectors ...\n";
        MediaWords::DBI::Stories::add_vectors( $db, $story );
    }
    
    print "processing stories done.\n";
}

# get stories from database, including content, text, tags, sentences, sentence_words, and story_sentence_words
sub get_expanded_stories
{
    my ( $db, $feed ) = @_;
    
    my $stories = $db->query( "select s.* from stories s, feeds_stories_map fsm " .
                              "  where s.stories_id = fsm.stories_id and fsm.feeds_id = ?", 
                              $feed->{ feeds_id } )->hashes;

    for my $story ( @{ $stories } )
    {
        $story->{ content } = ${ MediaWords::DBI::Stories::fetch_content( $db, $story ) };
        $story->{ extracted_text } = MediaWords::DBI::Stories::get_text( $db, $story );
        $story->{ tags } = MediaWords::DBI::Stories::get_db_module_tags( $db, $story, 'NYTTopics' );
        
        $story->{ story_words } = $db->query( "select * from story_words where stories_id = ?", $story->{ stories_id } )->hashes;
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
            for my $field ( qw(publish_date description url guid extracted_text) )
            {
                is( $story->{ $field }, $test_story->{ $field }, "story $field match" );
            }
            
            ok( $story->{ content } eq $test_story->{ content}, "story content matches" );
            
            is( scalar( @{ $story->{ tags } } ), scalar( @{ $test_story->{ tags } } ), "story tags count" );
            is( scalar( @{ $story->{ story_words } } ), scalar( @{ $test_story->{ story_words } } ), "story words count" );
        }
        
        delete( $test_story_hash->{ $story->{ title } } );
    }        
    
}

# store the stories as test data to compare against in subsequent runs
sub dump_stories
{
    my ( $db, $feed ) = @_;
    
    my $stories = get_expanded_stories( $db, $feed );
 
    MediaWords::Test::Data::store_test_data( 'crawler_stories', $stories );        
}

sub main 
{            

    my ( $dump ) = @ARGV;

    MediaWords::Test::DB::test_on_temporary_database
    ( sub {
        my ( $db ) = @_;
        
        my $feed = add_test_feed( $db );
            
        run_crawler();
        
        process_stories( $db );
        
        if ( $dump eq '-d' )
        {
            dump_stories( $db, $feed );
        }

        test_stories( $db, $feed );
    } );

}

main();


