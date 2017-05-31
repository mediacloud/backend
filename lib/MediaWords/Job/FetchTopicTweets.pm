package MediaWords::Job::FetchTopicTweets;

=head1 NAME

MediaWords::Job::FetchTopicTweets - fetch tweets relevant to a topic and store them in the topic_tweets table

=head1 DESCRIPTION

Use the Crimson Hexagon API to lookup tweets relevant to a topic, then fetch each of those tweets from twitter.

=cut

use strict;
use warnings;

use Moose;
with 'MediaWords::AbstractJob';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use List::MoreUtils;
use Net::Twitter;
use Date::Parse;

use MediaWords::DB;
use MediaWords::Util::DateTime;
use MediaWords::Util::JSON;
use MediaWords::Util::Web;

my $_api_host = undef;

=head1 METHODS

=cut

# fetch the list of tweets from the ch api.  return only 500 posts unless $fetch_10k_posts is true.
sub _fetch_ch_posts ($$)
{
    my ( $ch_monitor_id, $day ) = @_;

    my $ua = MediaWords::Util::Web::UserAgent->new();
    $ua->set_max_size( 100 * 1024 * 1024 );
    $ua->set_timeout( 90 );
    $ua->set_timing( '1,2,4,8,16,32,64,128,256,512' );

    my $key = MediaWords::Util::Config::get_config->{ crimson_hexagon }->{ key };
    LOGDIE( "no crimson hexagon key in mediawords.yml at //crimson_hexagon/key." ) unless ( $key );

    my $next_day = MediaWords::Util::SQL::increment_day( $day );

    my $url = _get_ch_api_url() . "?auth=$key&id=$ch_monitor_id&start=$day&end=$next_day&extendLimit=true";

    DEBUG( "CH URL: $url" );

    my $response = $ua->get( $url );

    if ( !$response->is_success )
    {
        LOGDIE( "error fetching posts: " . $response->as_string );
    }

    my $decoded_content = $response->decoded_content;

    my $data;
    eval { $data = MediaWords::Util::JSON::decode_json( $decoded_content ); };

    LOGDIE( "Unable to parse JSON from url $url: $@ " . substr( $decoded_content, 0, 1024 ) . " ..." ) unless ( $data );

    LOGDIE( "Unknown response status: '$data->{ status }'" ) unless ( $data->{ status } eq 'success' );

    return $data;
}

# add a row to topic_tweet_day if it does not already exist.  fetch data for new row from CH
sub _add_topic_tweet_single_day ($$$)
{
    my ( $db, $topic, $day ) = @_;

    my $topic_tweet_day = $db->query( <<SQL, $topic->{ topics_id }, $day )->hash;
select * from topic_tweet_days where topics_id = \$1 and day = \$2
SQL

    return if ( $topic_tweet_day && $topic_tweet_day->{ tweets_fetched } );

    # if we have a ttd but had not finished fetching tweets, delete it and start over
    $db->delete_by_id( 'topic_tweet_days', $topic_tweet_day->{ topic_tweet_days_id } ) if ( $topic_tweet_day );

    my $ch_posts = _fetch_ch_posts( $topic->{ ch_monitor_id }, $day );

    my $tweet_count = $ch_posts->{ totalPostsAvailable };

    my $num_ch_tweets = scalar( @{ $ch_posts->{ posts } } );

    $topic_tweet_day = $db->create(
        'topic_tweet_days',
        {
            topics_id      => $topic->{ topics_id },
            day            => $day,
            tweet_count    => $tweet_count,
            num_ch_tweets  => $num_ch_tweets,
            tweets_fetched => 'false'
        }
    );

    $topic_tweet_day->{ ch_posts } = $ch_posts;

    return $topic_tweet_day;
}

# for each day within the topic date range, find or create a topic_tweet_day row.
sub _add_topic_tweet_days ($$)
{
    my ( $db, $topic ) = @_;

    my $twitter = _get_twitter_handle();

    my $date = $topic->{ start_date };
    while ( $date le $topic->{ end_date } )
    {
        my $topic_tweet_day = _add_topic_tweet_single_day( $db, $topic, $date );
        _fetch_tweets_for_day( $db, $twitter, $topic, $topic_tweet_day ) if ( $topic_tweet_day );

        $date = MediaWords::Util::SQL::increment_day( $date );
    }

}

# given a set of ch_posts, fetch data from twitter about each tweet and attach it under the $ch->{ tweet } field
sub _add_tweets_to_ch_posts
{
    my ( $twitter, $ch_posts ) = @_;

    DEBUG( "fetching tweets for " . scalar( @{ $ch_posts } ) . " tweets" );

    LOGDIE( "more than 100 posts in $ch_posts" ) unless ( scalar( @{ $ch_posts } ) <= 500 );

    my $ch_post_lookup = {};
    for my $ch_post ( @{ $ch_posts } )
    {
        LOGDIE( "Unable to parse id from tweet url: $ch_post->{ url }" ) unless ( $ch_post->{ url } =~ m~/status/(\d+)~ );
        my $tweet_id = $1;

        $ch_post->{ tweet_id } = $tweet_id;
        $ch_post_lookup->{ $tweet_id } = $ch_post;
    }

    my $tweet_ids = [ keys( %{ $ch_post_lookup } ) ];

    my $tweets;
    my $twitter_retries = 0;
    while ( !$tweets && ( ++$twitter_retries <= 10 ) )
    {
        eval {
            $tweets = $twitter->lookup_statuses( { id => $tweet_ids, include_entities => 'true', trim_user => 'false' } );
        };
        if ( !$tweets )
        {
            my $sleep = 2 * ( $twitter_retries**2 );
            DEBUG( "twitter fetch error.  waiting $sleep seconds before retry ..." );
            sleep( $sleep );
        }
    }

    die( "unable to fetch tweets: $@ " ) unless ( $tweets );

    for my $tweet ( @{ $tweets } )
    {
        if ( my $ch_post = $ch_post_lookup->{ $tweet->{ id } } )
        {
            $ch_post->{ tweet } = $tweet;
        }
        else
        {
            LOGDIE( "no post found for tweet id $tweet->{ id }" );
        }
    }

    map { DEBUG( "no tweet fetched for url $_->{ url }" ); } ( grep { !$_->{ tweet } } @{ $ch_posts } );
}

# using the data in ch_post, store the tweet in topic_tweets and its urls in topic_tweet_urls
sub _store_tweet_and_urls($$$$)
{
    my ( $db, $topic, $topic_tweet_day, $ch_post ) = @_;

    my $created_at = $ch_post->{ tweet }->{ created_at };
    my $publish_date =
      $created_at
      ? MediaWords::Util::SQL::get_sql_date_from_epoch( Date::Parse::str2time( $created_at ) )
      : MediaWords::UTil::SQL::sql_now();

    my $topic_tweet = {
        topic_tweet_days_id => $topic_tweet_day->{ topic_tweet_days_id },
        data                => MediaWords::Util::JSON::encode_json( $ch_post ),
        content             => $ch_post->{ tweet }->{ text },
        tweet_id            => $ch_post->{ tweet_id },
        publish_date        => $publish_date,
        twitter_user        => $ch_post->{ tweet }->{ user }->{ screen_name }
    };

    $topic_tweet = $db->create( 'topic_tweets', $topic_tweet );

    my $urls_inserted;
    for my $url_data ( @{ $ch_post->{ tweet }->{ entities }->{ urls } } )
    {
        my $url = $url_data->{ expanded_url };

        next if ( $urls_inserted->{ $url } );
        $urls_inserted->{ $url } = 1;

        $db->create(
            'topic_tweet_urls',
            {
                topic_tweets_id => $topic_tweet->{ topic_tweets_id },
                url             => substr( $url, 0, 1024 )
            }
        );
    }
}

# if tweets_fetched is false for the given topic_tweet_days row, fetch the tweets for the given day by querying
# the list of tweets from CH and then fetching each tweet from twitter.
sub _fetch_tweets_for_day($$$$)
{
    my ( $db, $twitter, $topic, $topic_tweet_day ) = @_;

    return if ( $topic_tweet_day->{ tweets_fetched } );

    # my $ch_posts_data = _fetch_ch_posts( $topic->{ ch_monitor_id }, $topic_tweet_day->{ day } );

    my $ch_posts_data = $topic_tweet_day->{ ch_posts };

    LOGDIE( "no 'posts' field found in JSON result for topic $topic->{ topics_id } day $topic_tweet_day->{ day }" )
      unless ( $ch_posts_data->{ posts } );

    my $ch_posts = $ch_posts_data->{ posts };

    DEBUG(
        "adding " . scalar( @{ $ch_posts } ) . " tweets for topic $topic->{ topics_id } day $topic_tweet_day->{ day } ..." );

    # we can get 100 posts at a time from twitter
    my $get_posts_chunk = List::MoreUtils::natatime( 100, @{ $ch_posts } );
    while ( my @ch_posts_chunk = $get_posts_chunk->() )
    {
        _add_tweets_to_ch_posts( $twitter, \@ch_posts_chunk );
    }

    $db->begin();

    DEBUG( "inserting into topic_tweets ..." );

    map { _store_tweet_and_urls( $db, $topic, $topic_tweet_day, $_ ) } ( grep { $_->{ tweet } } @{ $ch_posts } );

    my $num_deleted_tweets = scalar( grep { !$_->{ tweet } } @{ $ch_posts } );
    $topic_tweet_day->{ num_ch_tweets } -= $num_deleted_tweets;

    $db->query( <<SQL, $topic_tweet_day->{ topic_tweet_days_id }, $topic_tweet_day->{ num_ch_tweets } );
update topic_tweet_days set tweets_fetched = true, num_ch_tweets = \$2 where topic_tweet_days_id = \$1
SQL

    $db->commit();

    DEBUG( "done inserting into topic_tweets" );
}

# get Net::Twitter handle using auth info from mediawords.yml
sub _get_twitter_handle
{
    my $config = MediaWords::Util::Config::get_config;

    map { die( "missing config for //twitter/$_" ) unless ( $config->{ twitter }->{ $_ } ) }
      qw(consumer_key consumer_secret access_token access_token_secret);

    my $twitter = Net::Twitter->new(
        traits              => [ qw/API::RESTv1_1/ ],
        ssl                 => 0,
        apiurl              => _get_twitter_api_url(),
        consumer_key        => $config->{ twitter }->{ consumer_key },
        consumer_secret     => $config->{ twitter }->{ consumer_secret },
        access_token        => $config->{ twitter }->{ access_token },
        access_token_secret => $config->{ twitter }->{ access_token_secret },
    );
}

=head2 run( $self, $args )

Accepts a topics_id arg.

Fetch list of tweets within a Crimson Hexagon monitor based on the ch_monitor_id of the given topic.  If there is no
ch_monitor_id for the topic, do nothing.

Crimson Hexagon returns up to 10k randomly sampled tweets per posts fetch, and each posts fetch can be restricted
down to a single day.  This call fetches tweets from CH day by day, up to a total of 1 million tweets for a single
topic for the whole date range combined.  The call normalizes the number of tweets returned for each day so that
each day has the same percentage of all tweets found on that day.  So if there werwe 20,000 tweets found on the
busiest day, each day will use at most 50% of the returned tweets for the day.

One call to this function takes care of both fetching the list of all tweets from CH and fetching each of those
tweets from twitter (CH does not provide the tweet content, only the url).  Each day's worth of tweets will be
recorded in topic_tweet_days, and subsequent calls to the function will not refetch a given day for a given topic,
but each call will fetch any days newly included in the date range of the topic given a topic dates change.

=cut

sub run($;$)
{
    my ( $self, $args ) = @_;

    my $topics_id = $args->{ topics_id };
    LOGDIE( "must specify topics_id" ) unless ( $topics_id );

    my $db = MediaWords::DB::connect_to_db();

    my $topic = $db->require_by_id( 'topics', $topics_id );

    my $ch_monitor_id = $topic->{ ch_monitor_id };

    if ( !$ch_monitor_id )
    {
        DEBUG( "returning after noop because topic $topics_id has a null ch_monitor_id" );
        return;
    }

    _add_topic_tweet_days( $db, $topic );

    # my $twitter = _get_twitter_handle();
    #
    # map { _fetch_tweets_for_day( $db, $twitter, $topic, $_ ) } @{ $topic_tweet_days };
}

=head2 set_api_host( $host )

Set the scheme, host, and port in schem://host.name:port format to use for both ch and twitter api calls for testing purposes.

=cut

sub set_api_host ($$)
{
    my ( $class, $host ) = @_;

    $_api_host = $host;
}

# return the url for the ch monitor/posts call
sub _get_ch_api_url
{
    my $host = $_api_host ? $_api_host : 'https://api.crimsonhexagon.com';

    return "$host/api/monitor/posts";
}

# return the url to pass as the apiurl to the Net::Twitter module
sub _get_twitter_api_url
{
    my $host = $_api_host ? $_api_host : 'https://api.twitter.com/1.1';

    return $host;
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
