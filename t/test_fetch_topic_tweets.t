use strict;
use warnings;

# test MediaWords::Job::FetchTopicTweets

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use HTTP::HashServer;
use Readonly;
use Test::More;

use MediaWords::TM;
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

# number of mock urls and users -- the mock api roughly distributes this many unique urls
# and users among the tweets
Readonly my $NUM_MOCK_URLS  => 250;
Readonly my $NUM_MOCK_USERS => 75;

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
        my $url_id  = $id % $NUM_MOCK_URLS;
        my $user_id = $id % $NUM_MOCK_USERS;

        # all we use is id, text, and created_by, so just test for those
        push(
            @{ $tweets },
            {
                id         => $id,
                text       => "sample tweet for id $id",
                created_at => 'Wed Jun 06 20:07:10 +0000 2016',
                user       => { screen_name => "user-$user_id" },
                entities   => { urls => [ { expanded_url => "http://localhost:$PORT/tweet_url?id=$url_id" } ] }
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

    my $topic_tweets = $db->query( <<SQL, $topic->{ topics_id } )->hashes;
select *
    from topic_tweets tt
        join topic_tweet_days ttd using ( topic_tweet_days_id )
    where
        ttd.topics_id = ?
SQL

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

# validate that topic_links is what it should be by rebuilding the topic links directly from the
# ch + twitter json data stored in topic_tweets and generating a link list using perl
sub validate_topic_links
{
    my ( $db, $twitter_topic ) = @_;

    my $topic_tweets = $db->query( <<SQL, $twitter_topic->{ twitter_parent_topics_id } )->hashes;
select tt.* from topic_tweets tt join topic_tweet_days ttd using ( topic_tweet_days_id ) where ttd.topics_id = \$1
SQL

    my $expected_story_tweet_counts = {};
    my $user_stories_lookup         = {};
    for my $topic_tweet ( @{ $topic_tweets } )
    {
        my $data = MediaWords::Util::JSON::decode_json( $topic_tweet->{ data } );
        ok( $data->{ url }, "topic tweet data has url" );

        my $tweet = $data->{ tweet } || next;

        my $user = $tweet->{ user }->{ screen_name };
        my $urls = [ map { $_->{ expanded_url } } @{ $tweet->{ entities }->{ urls } } ];
        for my $url ( @{ $urls } )
        {
            # assume that the stories_ids have gotten into topic_seed_urls becasue we tested for that already
            my ( $stories_id ) = $db->query( <<SQL, $twitter_topic->{ topics_id }, $url )->flat;
select stories_id from topic_seed_urls where topics_id = \$1 and url = \$2
SQL
            next unless ( $stories_id );

            $expected_story_tweet_counts->{ $stories_id }++;
            $user_stories_lookup->{ $user }->{ $stories_id } = 1 if ( $stories_id );
        }
    }

    my $expected_link_lookup = {};
    while ( my ( $user, $stories_lookup ) = each( %{ $user_stories_lookup } ) )
    {
        my $stories_ids = [ keys( %{ $stories_lookup } ) ];
        for my $a ( @{ $stories_ids } )
        {
            for my $b ( @{ $stories_ids } )
            {
                $expected_link_lookup->{ $a }->{ $b } = 1 unless ( $a == $b );
            }
        }
    }

    my $expected_num_links = 0;
    map { $expected_num_links += scalar( keys( %{ $expected_link_lookup->{ $_ } } ) ) } keys( %{ $expected_link_lookup } );

    my $topic_links = $db->query( "select * from topic_links where topics_id = \$1", $twitter_topic->{ topics_id } )->hashes;

    is( scalar( @{ $topic_links } ), $expected_num_links, "number of topic links match" );

    for my $topic_link ( @{ $topic_links } )
    {
        my $stories_id     = $topic_link->{ stories_id };
        my $ref_stories_id = $topic_link->{ ref_stories_id };
        ok( $expected_link_lookup->{ $stories_id }->{ $ref_stories_id },
            "valid topic link: $stories_id -> $ref_stories_id" );
    }

    my $timespan = MediaWords::TM::get_latest_overall_timespan( $db, $twitter_topic->{ topics_id } );
    my $story_link_counts = $db->query( <<SQL, $timespan->{ timespans_id } )->hashes;
select * from snap.story_link_counts where timespans_id = \$1
SQL

    for my $slc ( @{ $story_link_counts } )
    {
        is( $slc->{ simple_tweet_count }, $expected_story_tweet_counts->{ $slc->{ stories_id } }, "simple tweet count" );
    }
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

    is( $twitter_topic->{ state }, 'ready', "twitter topic state" );

    my ( $num_matching_seed_urls ) = $db->query( <<SQL, $parent_topic->{ topics_id } )->flat;
select count(*) from topic_tweet_full_urls where parent_topics_id = \$1
SQL

    my ( $expected_num_urls ) = $db->query( "select count(*) from topic_tweet_urls" )->flat;
    is( $num_matching_seed_urls, $expected_num_urls, "seed urls match topic tweet urls" );

    my ( $num_dead_tweets ) = $db->query( <<SQL, $twitter_topic->{ topics_id } )->flat;
select count(*)
    from topic_dead_links tdl
        join topic_tweet_full_urls ttfu on
            ( ttfu.twitter_topics_id = tdl.topics_id and tdl.url = ttfu.url )
    where
        tdl.topics_id = \$1
SQL

    my ( $num_null_story_seed_urls ) = $db->query( <<SQL, $twitter_topic->{ topics_id } )->flat;
select count(*) from topic_seed_urls where stories_id is null and topics_id = \$1
SQL
    ok( $num_null_story_seed_urls <= $num_dead_tweets,
        "number of topic_seed_urls with null stories_id: $num_null_story_seed_urls <= $num_dead_tweets" );

    my ( $num_matching_topic_stories ) = $db->query( <<SQL, $twitter_topic->{ topics_id } )->flat;
select count(*) from topic_tweet_full_urls where stories_id is not null and twitter_topics_id = \$1
SQL

    my $num_processed_stories = $num_matching_topic_stories + $num_dead_tweets;

    is( $num_processed_stories, $expected_num_urls, "number of processed urls in twitter topic" );

    validate_topic_links( $db, $twitter_topic );
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

# if the twitter and ch keys are setup, run the tests on the external apis
sub run_tests_on_external_apis
{
    my $config = MediaWords::Util::Config::get_config();

    if ( !$config->{ twitter }->{ consumer_secret } || !$config->{ crimson_hexagon }->{ key } )
    {
        WARN( "SKIPPING EXTERNAL APIS BECAUSE TWITTER AND/OR CRIMSON HEXAGON KEYS NOT FOUND" );
        return;
    }

    MediaWords::Test::DB::test_on_test_database( \&test_fetch_topic_tweets );
}

sub run_tests_on_mock_apis
{
    my $hs = HTTP::HashServer->new(
        $PORT,
        {
            '/api/monitor/posts'    => { callback => \&mock_ch_posts },
            '/statuses/lookup.json' => { callback => \&mock_twitter_lookup },
            '/tweet_url'            => { callback => \&mock_tweet_url }
        }
    );
    $hs->start();

    MediaWords::Job::FetchTopicTweets->set_api_host( "http://localhost:$PORT" );
    my $config = MediaWords::Util::Config::get_config();

    # set dummy values so that we can hit the mock apis without the underlying modules complaining
    $config->{ crimson_hexagon }->{ key } = 'TEST';
    map { $config->{ twitter }->{ $_ } = 'TEST' } qw/consumer_key consumer_secret access_token access_token_secret/;

    eval { MediaWords::Test::DB::test_on_test_database( \&test_fetch_topic_tweets ); };
    my $test_error = $@;

    $hs->stop();

    die( $test_error ) if ( $test_error );

}

sub main
{
    # topic date modeling confuses perl TAP for some reason
    MediaWords::Util::Config::get_config()->{ mediawords }->{ topic_model_reps } = 0;

    #run_tests_on_external_apis();

    run_tests_on_mock_apis();

    done_testing();
}

main();
