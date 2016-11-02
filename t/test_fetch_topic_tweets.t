use strict;
use warnings;

# test MediaWords::Job::FetchTopicTweets

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use HTTP::HashServer;
use Readonly;
use Test::More;

use MediaWords::TM::Mine;
use MediaWords::Test::DB;
use MediaWords::Test::Data;
use MediaWords::Test::ExternalAPI;
use MediaWords::Util::Config;
use MediaWords::Util::JSON;

# test port for mock api server
Readonly my $PORT => 8899;

# id for valid monitor at CH (valid id needed only if MC_TEST_EXTERNAL_APIS set)
Readonly my $CH_MONITOR_ID => 4488828184;

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

# send a simple text page for use mocking tweet url pages
sub mock_tweet_url
{
    my ( $self, $cgi ) = @_;

    my $id = $cgi->param( 'id' );

    die( "id param must be specified" ) unless ( $id );

    print <<HTTP;
HTTP/1.1 200 OK
Content-Type: text/plain

Sample page for tweet $id url
HTTP
}

sub mock_twitter_lookup
{
    my ( $self, $cgi ) = @_;

    my $id_list = $cgi->param( 'id' );

    die( "id param must be specified" ) unless ( $id_list );

    my $ids = [ split( ',', $id_list ) ];

    die( "at least one id must be specified" ) unless ( @{ $ids } );

    die( "all ids must be integers" ) if ( grep { $_ =~ /[^0-9]/ } @{ $ids } );

    my $num_errors = ( scalar( @{ $ids } ) > 10 ) ? 3 : 0;

    # simulate twitter not being able to find some ids, which is typical
    map { pop( @{ $ids } ) } ( 1 .. $num_errors );

    my $tweets = [];
    for my $id ( @{ $ids } )
    {
        # all we use is id, text, and created_by, so just test for those
        push(
            @{ $tweets },
            {
                id         => $id,
                text       => "sample tweet for id $id t.co",
                created_at => 'Wed Jun 06 20:07:10 +0000 2016',
                user       => { screen_name => "user-$id" },
                entities   => { urls => [ { expanded_url => "http://localhost:$PORT/tweet_url?id=$id" } ] }
            }
        );
    }

    my $json = MediaWords::Util::JSON::encode_json( $tweets );

    print <<HTTP;
HTTP/1.1 200 OK
Content-Type: application/json

$json
HTTP
}

# verify that topic_tweet_urls match what's in the tweet json data as saved in topic_tweets
sub validate_topic_tweet_urls($$)
{
    my ( $db, $topic ) = @_;

    my $topic_tweets = $db->query( "select * from topic_tweets where topics_id = \$1", $topic->{ topics_id } )->hashes;

    my $num_topic_tweets = scalar( @{ $topic_tweets } );

    my $expected_num_urls = 0;
    for my $topic_tweet ( @{ $topic_tweets } )
    {
        my $data = MediaWords::Util::JSON::decode_json( $topic_tweet->{ data } );
        $expected_num_urls += scalar( @{ $data->{ tweet }->{ entities }->{ urls } } );
    }

    # first sanity check to make sure we got some urls
    my ( $num_urls ) = $db->query( "select count(*) from topic_tweet_urls" )->flat;
    is( $num_urls, $expected_num_urls, "number of urls" );

    my $total_json_urls = 0;
    for my $topic_tweet ( @{ $topic_tweets } )
    {
        my $ch_post = MediaWords::Util::JSON::decode_json( $topic_tweet->{ data } );
        my $expected_urls = [ map { $_->{ expanded_url } } @{ $ch_post->{ tweet }->{ entities }->{ urls } } ];
        $total_json_urls += scalar( @{ $expected_urls } );

        for my $expected_url ( @{ $expected_urls } )
        {
            my $got_url = $db->query( "select * from topic_tweet_urls where url = \$1", $expected_url )->hash;
            ok( $got_url, "found url $expected_url" );
        }
    }

    is( $total_json_urls, $num_urls, "num of urls in json vs. num of urls in database" );
}

# verify that topic data has been properly created, including topic_seed_urls, topic_stories, and topic_links
sub validate_topic_data($$)
{
    my ( $db, $parent_topic ) = @_;

    my $twitter_topic = $db->query( <<SQL, $parent_topic->{ topics_id } )->hash;
select * from topics where twitter_parent_topics_id = \$1
SQL

    ok( $twitter_topic, "twitter topic created" );
    is( $twitter_topic->{ name }, "$parent_topic->{ name } (twitter)", "twitter topic name" );

    my ( $num_matching_seed_urls ) = $db->query( <<SQL, $parent_topic->{ topics_id } )->flat;
select count(*)
    from topic_seed_urls tsu, topic_tweet_urls ttu, topic_tweets tt, topics t
    where
        t.twitter_parent_topics_id = \$1 and
        t.twitter_parent_topics_id = tt.topics_id and
        tt.topic_tweets_id = ttu.topic_tweets_id and
        tsu.url = ttu.url and
        tsu.topics_id = t.topics_id
SQL

    my ( $expected_num_urls ) = $db->query( "select count(*) from topic_tweet_urls" )->flat;
    is( $num_matching_seed_urls, $expected_num_urls, "seed urls match topic tweet urls" );

    my ( $num_dead_tweets ) = $db->query( <<SQL, $twitter_topic->{ topics_id } )->flat;
select count(*)
    from
        topics t
        join topic_dead_links tdl on ( t.topics_id = tdl.topics_id )
        join topic_tweets tt on ( t.twitter_parent_topics_id = tt.topics_id )
        join topic_tweet_urls ttu on ( ttu.url = tdl.url and ttu.topic_tweets_id = tt.topic_tweets_id )
    where
        t.topics_id = \$1
SQL

    my ( $num_null_story_seed_urls ) = $db->query( <<SQL, $twitter_topic->{ topics_id } )->flat;
select count(*) from topic_seed_urls where stories_id is null and topics_id = \$1
SQL
    ok( $num_null_story_seed_urls <= $num_dead_tweets,
        "number of topic_seed_urls with null stories_id: $num_null_story_seed_urls <= $num_dead_tweets" );

    my ( $num_matching_topic_stories ) = $db->query( <<SQL, $twitter_topic->{ topics_id } )->flat;
select count(*)
    from
        topics t
        join topic_stories ts on ( t.topics_id = ts.topics_id )
        join topic_seed_urls tsu on ( tsu.stories_id = ts.stories_id and tsu.topics_id = ts.topics_id )
        join topic_tweets tt on ( t.twitter_parent_topics_id = tt.topics_id )
        join topic_tweet_urls ttu on ( ttu.url = tsu.url and ttu.topic_tweets_id = tt.topic_tweets_id )
    where
        t.topics_id = \$1
SQL

    my $num_processed_stories = $num_matching_topic_stories + $num_dead_tweets;

    is( $num_processed_stories, $expected_num_urls, "number of processed urls in twitter topic" );
}

# core testing functionality
sub test_fetch_topic_tweets
{
    my ( $db ) = @_;

    my $topic = MediaWords::Test::DB::create_test_topic( $db, 'tweet topic' );

    $topic->{ ch_monitor_id } = $CH_MONITOR_ID;
    $db->update_by_id( 'topics', $topic->{ topics_id }, $topic );
    $db->query( <<SQL, $topic->{ topics_id }, '2016-01-01', '2016-01-05' );
update topic_dates set start_date = \$2, end_date = \$3 where topics_id = \$1
SQL

    MediaWords::TM::Mine::mine_topic( $db, $topic, { test_mode => 1 } );

    my $test_dates = get_test_dates();
    for my $date ( @{ $test_dates } )
    {
        my $topic_tweet_date = $db->query( <<SQL, $topic->{ topics_id }, $date )->hash;
select * from topic_tweet_days where topics_id = \$1 and day = \$2
SQL
        ok( $topic_tweet_date, "topic_tweet_date created for $date" );
    }

    my ( $expected_num_ch_tweets ) = $db->query( "select sum( num_ch_tweets ) from topic_tweet_days" )->flat;
    my ( $num_tweets_inserted )    = $db->query( "select count(*) from topic_tweets" )->flat;
    is( $num_tweets_inserted, $expected_num_ch_tweets, "num of topic_tweets inserted" );

    my ( $num_null_text_tweets ) = $db->query( "select count(*) from topic_tweets where content is null" )->flat;
    is( $num_null_text_tweets, 0, "number of null text tweets" );

    my ( $num_null_date_tweets ) = $db->query( "select count(*) from topic_tweets where publish_date is null" )->flat;
    is( $num_null_date_tweets, 0, "number of null publish_date tweets" );

    my ( $num_short_tweets ) = $db->query( "select count(*) from topic_tweets where length( content ) < 16" )->flat;
    is( $num_short_tweets, 0, "number of short tweets" );

    my ( $num_short_users ) = $db->query( "select count(*) from topic_tweets where length( twitter_user ) < 3" )->flat;
    is( $num_short_users, 0, "number of short users" );

    validate_topic_tweet_urls( $db, $topic );
    validate_topic_data( $db, $topic );
}

sub main
{
    # topic date modeling confuses perl TAP for some reason
    MediaWords::Util::Config::get_config()->{ mediawords }->{ topic_model_reps } = 0;

    my $hs = HTTP::HashServer->new(
        $PORT,
        {
            '/api/monitor/posts'    => { callback => \&mock_ch_posts },
            '/statuses/lookup.json' => { callback => \&mock_twitter_lookup },
            '/tweet_url'            => { callback => \&mock_tweet_url }
        }
    );
    $hs->start();

    if ( !MediaWords::Test::ExternalAPI::use_external_api() )
    {
        MediaWords::Job::FetchTopicTweets->set_api_host( "http://localhost:$PORT" );
        MediaWords::Util::Config::get_config->{ crimson_hexagon }->{ key } = 'TEST';
    }

    eval { MediaWords::Test::DB::test_on_test_database( \&test_fetch_topic_tweets ); };
    my $test_error = $@;

    $hs->stop();

    die( $test_error ) if ( $test_error );

    done_testing();
}

main();
