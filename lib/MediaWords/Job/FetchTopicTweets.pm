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

BEGIN
{
    use FindBin;

    # "lib/" relative to "local/bin/mjm_worker.pl":
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Util::Web;
use MediaWords::Util::JSON;

my $_ch_api_url = "https://api.crimsonhexagon.com/api/monitor/posts";

=head1 METHODS

=cut

# fetch the list of tweets from the ch api.  return only 500 posts unless $fetch_10k_posts is true.
sub _fetch_ch_posts ($$;$)
{
    my ( $ch_monitor_id, $day, $fetch_10k_posts ) = @_;

    my $ua = MediaWords::Util::Web::UserAgent();

    my $key = MediaWords::Util::Config::get_config->{ crimson_hexagon }->{ key };
    LOGDIE( "no crimson hexagon key in mediawords.yml at //crimson_hexagon/key." ) unless ( $key );

    my $next_day = MediaWords::Util::SQL::increment_day( $day );

    my $url = "$_ch_api_url?auth=-$key&id=$ch_monitor_id&start=$day&end=$next_day";

    my $response = $ua->get( $url );

    if ( !$response->is_success )
    {
        LOGDIE( "error fetching posts: " . $response->as_string );
    }

    my $decoded_content = $response->decoded_content;

    my $data;
    eval { $data = MediaWords::Util::JSON::decode_json( $decoded_content ); };

    LOGDIE( "Unable to parse json from url $url: $@ " . substr( $decoded_content, 0, 1024 ) ) unless ( $data );

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

    return if ( $topic_tweet_day );

    my $ch_posts = _fetch_ch_posts( $topic->{ ch_monitor_id }, $day );

    my $num_tweets = $ch_posts->{ totalPostsAvailable };

    $db->create(
        'topic_tweet_days',
        {
            topics_id      => $topic->{ topics_id },
            day            => $day,
            num_tweets     => $num_tweets,
            tweets_fetched => 'false'
        }
    );
}

# for each day within the topic date range, find or create a topic_tweet_day row.
sub _get_topic_tweet_days ($$)
{
    my ( $db, $topic ) = @_;

    $topic = $db->query( "select * from topics_with_dates where topics_id = ?", $topic->{ topics_id } )->hash;

    my $date = $topic->{ start_date };
    while ( $date le $topic->{ end_date } )
    {
        _add_topic_tweet_single_day( $db, $topic, $date );
        $date = MediaWords::Util::SQL::increment_day( $date );
    }

    my $topic_tweet_days = $db->query( <<SQL, $topic->{ topics_id }, $topic->{ start_date }, $topic->{ end_date } )->hashes;
select * from topic_tweet_days where topics_id = \$1 and day between \$2 and \$3
SQL

    return $topic_tweet_days;
}

# if tweets_fetched is false for the given topic_tweet_days row, fetch the tweets for the given day by querying
# the list of tweets from CH and then fetching each tweet from twitter
sub _fetch_tweets
{
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

    my $topic_tweet_days = _get_topic_tweet_days( $db, $topic );

    map { _fetch_tweets( $db, $topic, $_ ) } @{ $topic_tweet_days };
}

=head2 set_ch_api_url( $url )

Set the full api url used to access crimson hexagon.

=cut

sub set_api_url ($$)
{
    my ( $class, $url ) = @_;

    $_ch_api_url = $url;
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
