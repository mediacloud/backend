use strict;
use warnings;

use utf8;
use Test::NoWarnings;
use Test::More tests => 35;

use MediaWords::Test::DB;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Util::Twitter' );
}

my $_last_request_time;

sub test_request()
{
    my $ua = MediaWords::Util::Web::UserAgent;

    my @urls = (

        # URLs with #fragment
        'http://www.nbcnews.com/#/health/health-news/inside-ebola-clinic-doctors-fight-out-control-virus-%20n150391',
        'http://www.nbcnews.com/#/health/',
        'http://www.nbcnews.com/#/health',
        'http://www.nbcnews.com/#/',
        'http://foo.com/#/bar/',

        # Twitter API works only when the #fragment starts with a slash (/)
        # 'http://www.nbcnews.com/#health',
        # 'http://www.nbcnews.com/#health/',

        # URLs with ~tilde
        'http://cyber.law.harvard.edu/~lvaliukas/test.html/',
        'http://cyber.law.harvard.edu/~lvaliukas/test.html/#/foo'
    );

    foreach my $url ( @urls )
    {
        my $data = MediaWords::Util::Twitter::_get_single_url_json( $ua, $url );
        ok( $data,            "Data is defined for URL $url" );
        ok( $data->{ 'url' }, "Data has 'url' key for URL $url" );
        is( $data->{ 'url' }, $url, "URL matches for URL $url" );
    }
}

sub test_tweet_count($)
{
    my ( $db ) = @_;

    my $popular_page_count =
      MediaWords::Util::Twitter::get_url_tweet_count( $db, 'https://dev.twitter.com/web/tweet-button' );
    ok( $popular_page_count > 900, "popular page count '$popular_page_count' should be big" );

    my $nyt_ferguson_count = MediaWords::Util::Twitter::get_url_tweet_count( $db,
        'http://www.nytimes.com/interactive/2014/08/13/us/ferguson-missouri-town-under-siege-after-police-shooting.html' );
    ok( $nyt_ferguson_count > 12000, "nyt ferguson count '$nyt_ferguson_count' should be greater than 12,000" );

    my $zero_count = MediaWords::Util::Twitter::get_url_tweet_count( $db,
        'http://cyber.law.harvard.edu/~lvaliukas/most-boring-blog-post.html' );
    ok( $zero_count == 0, "zero count '$zero_count' should be 0" );

    my $homepage_count = MediaWords::Util::Twitter::get_url_tweet_count( $db, 'http://cyber.law.harvard.edu/' );
    ok( $homepage_count == 0, "homepage count '$homepage_count' should be 0" );

    my $suspended_count =
      MediaWords::Util::Twitter::get_url_tweet_count( $db, 'https://twitter.com/Todd__Kincannon/status/518499096974614529' );
    ok( $suspended_count > 40, "suspended count '$suspended_count' should be > 40" );

    eval { MediaWords::Util::Twitter::get_url_tweet_count( $db, 'totally.bogus.url.123456' ); };
    ok( $@, 'Bogus URL' );
}

sub test_store_result($)
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::DB::create_test_story_stack( $db, { A => { B => [ 1, 2, 3 ] } } );

    my $story = $media->{ A }->{ feeds }->{ B }->{ stories }->{ 1 };

    $story->{ url } = 'https://dev.twitter.com/web/tweet-button';

    my $count = MediaWords::Util::Twitter::get_and_store_tweet_count( $db, $story );

    my $ss = $db->query( 'select * from story_statistics where stories_id = ?', $story->{ stories_id } )->hash;

    ok( $ss, 'story_statistics row exists after initial insert' );

    is( $ss->{ twitter_url_tweet_count }, $count, "stored url tweet count" );
    ok( !defined( $ss->{ twitter_url_tweet_count_error } ), "null url tweet count error" );

    $story->{ url } = 'foobar';

    eval { MediaWords::Util::Twitter::get_and_store_tweet_count( $db, $story ); };
    ok( $@, 'bogus URL should die() while fetching tweet count' );

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

    test_request();

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_tweet_count( $db );
            test_store_result( $db );
        }
    );
}

main();
