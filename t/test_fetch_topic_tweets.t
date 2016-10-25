use strict;
use warnings;

# test MediaWords::Job::FetchTopicTweets

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use HTTP::HashServer;
use Readonly;
use Test::More;

use MediaWords::Job::FetchTopicTweets;
use MediaWords::Test::DB;
use MediaWords::Test::Data;
use MediaWords::Test::ExternalAPI;
use MediaWords::Util::Config;

# test port for mock api server
Readonly my $PORT => 8899;

# id for valid monitor at CH (valid id needed only if MC_TEST_EXTERNAL_APIS set
Readonly my $CH_MONITOR_ID => 4404821226;

# return list of dates to test for
sub get_test_dates
{
    my $dates = [ map { "2016-01-0$_" } ( 1 .. 5 ) ];

    return $dates;
}

sub get_test_data
{
    my ( $date ) = @_;

    return MediaWords::Test::Data::read_test_file( "ch", "ch-posts-$date.json" );
}

sub mock_ch_posts
{
    my ( $self, $cgi ) = @_;

    DEBUG( "MOCK CH POSTS" );

    my $auth       = $cgi->param( 'auth' )  || LOGDIE( "missing auth param" );
    my $id         = $cgi->param( 'id' )    || LOGDIE( "missing id param" );
    my $start_date = $cgi->param( 'start' ) || LOGDIE( "missing start param" );
    my $end_date   = $cgi->param( 'end' )   || LOGDIE( "missing end param" );

    my $file_dates = get_test_dates();

    LOGDIE( "no test data for $start_date" ) unless ( grep { $_ eq $start_date } @{ $file_dates } );

    my $expected_end_date = MediaWords::Util::SQL::increment_day( $start_date );
    LOGDIE( "end_date expected to be '$expected_end_date' for mock api" ) unless ( $end_date eq $expected_end_date );

    my $json = get_test_data( $start_date );

    print <<HTTP
HTTP/1.1 200 OK
Content-Type: application/json

$json
HTTP
}

# core testing functionality
sub test_fetch_topic_tweets
{
    my ( $db ) = @_;

    my $topic = MediaWords::Test::DB::create_test_topic( $db, 'tweet topic' );

    $db->update_by_id( 'topics', $topic->{ topics_id }, { ch_monitor_id => $CH_MONITOR_ID } );
    $db->query( <<SQL, $topic->{ topics_id }, '2016-01-01', '2016-01-05' );
update topic_dates set start_date = \$2, end_date = \$3 where topics_id = \$1
SQL

    MediaWords::Job::FetchTopicTweets->run( { topics_id => $topic->{ topics_id } } );

    my $test_dates = get_test_dates();
    for my $date ( @{ $test_dates } )
    {
        # regexp parse the number of tweets from the data so that we don't use same json parsing code path
        my $expected_json = get_test_data( $date );
        LOGDIE( "unable to parse num of tweets for $date" ) unless ( $expected_json =~ /"totalPostsAvailable":(\d+)/ );
        my $expected_num_tweets = $1;

        my $topic_tweet_date = $db->query( <<SQL, $topic->{ topics_id }, $date )->hash;
select * from topic_tweet_days where topics_id = \$1 and day = \$2
SQL
        ok( $topic_tweet_date, "topic_tweet_date created for $date" );
        is( $topic_tweet_date->{ num_tweets }, $expected_num_tweets, "number of tweets for $date" );
    }

    DEBUG( "DONE" );
}

sub main
{
    my $hs = HTTP::HashServer->new( $PORT, { '/api/monitor/posts' => { callback => \&mock_ch_posts } } );
    $hs->start();

    if ( !MediaWords::Test::ExternalAPI::use_external_api() )
    {
        MediaWords::Job::FetchTopicTweets->set_api_url( "http://localhost:$PORT/api/monitor/posts" );
        MediaWords::Util::Config::get_config->{ crimson_hexagon }->{ key } = 'TEST';
    }

    MediaWords::Test::DB::test_on_test_database( \&test_fetch_topic_tweets );

    $hs->stop();

    done_testing();
}

main();
