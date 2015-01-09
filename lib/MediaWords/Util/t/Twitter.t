use strict;
use warnings;

use utf8;
use Test::NoWarnings;
use Test::More tests => 10;

use MediaWords::Test::DB;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Util::Twitter' );
}

my $_last_request_time;

sub test_tweet_count($)
{
    my ( $db ) = @_;

    my $google_count = MediaWords::Util::Twitter::get_url_tweet_count( $db, 'http://google.com' );

    my $nyt_ferguson_count = MediaWords::Util::Twitter::get_url_tweet_count( $db,
        'http://www.nytimes.com/interactive/2014/08/13/us/ferguson-missouri-town-under-siege-after-police-shooting.html' );

    my $zero_count = MediaWords::Util::Twitter::get_url_tweet_count( $db, 'http://totally.bogus.url.123456' );

    ok( $google_count > 21972863,    "google count '$google_count' shoudl be greater than 21972863" );
    ok( $nyt_ferguson_count > 12000, "nyt ferguson count '$nyt_ferguson_count' should be greater than 12,000" );
    ok( $zero_count == 0,            "zero count '$zero_count' should be 0" );
}

sub test_store_result($)
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::DB::create_test_story_stack( $db, { A => { B => [ 1, 2, 3 ] } } );

    my $story = $media->{ A }->{ feeds }->{ B }->{ stories }->{ 1 };

    $story->{ url } = 'http://google.com';

    my $count = MediaWords::Util::Twitter::get_and_store_tweet_count( $db, $story );

    my $ss = $db->query( 'select * from story_statistics where stories_id = ?', $story->{ stories_id } )->hash;

    ok( $ss, 'story_statistics row exists after initial insert' );

    is( $ss->{ twitter_url_tweet_count }, $count, "stored url tweet count" );
    ok( !defined( $ss->{ twitter_url_tweet_count_error } ), "null url tweet count error" );

    $story->{ url } = 'foobar';

    MediaWords::Util::Twitter::get_and_store_tweet_count( $db, $story );

    my $sse = $db->query( 'select * from story_statistics where stories_id = ?', $story->{ stories_id } )->hash;

    is( $sse->{ twitter_url_tweet_count }, 0, "stored url tweet count should 0 after error" );
    ok( defined( $sse->{ twitter_url_tweet_count_error } ), "stored url tweet count should contain error" );
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_tweet_count( $db );
            test_store_result( $db );
        }
    );
}

main();
