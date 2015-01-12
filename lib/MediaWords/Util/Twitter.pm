package MediaWords::Util::Twitter;

#
# Twitter API helper
#

use strict;
use warnings;

use URI::Escape;
use Readonly;

use MediaWords::Util::JSON;
use MediaWords::Util::URL;
use MediaWords::Util::Web;

sub _get_single_url_json
{
    my ( $ua, $url ) = @_;

    # this is mostly to be able to generate an error for testing
    unless ( MediaWords::Util::URL::is_http_url( $url ) )
    {
        die "Invalid URL: $url";
    }

    my $response = $ua->get( 'https://cdn.api.twitter.com/1/urls/count.json?url=' . uri_escape_utf8( $url ) );

    if ( !$response->is_success )
    {
        die( "error fetching tweet count for url '$url'" );
    }
    my $decoded_content = $response->decoded_content;

    my $data = MediaWords::Util::JSON::decode_json( $decoded_content );
    unless ( $data and ref( $data ) eq ref( {} ) )
    {
        die "Returned JSON is empty or invalid.";
    }

    return $data;
}

sub _get_single_url_tweet_count
{
    my ( $ua, $url ) = @_;

    my $data = _get_single_url_json( $ua, $url );

    return $data->{ count };
}

# use cdn.api.twitter.com/1/urls/count.json to get count of tweets referencing the given url, including all variants
# of the url we can figure out
#
# https://cdn.api.twitter.com/1/urls/count.json?url=http://www.theonion.com/articles/how-to-protect-yourself-against-ebola,37085
sub get_url_tweet_count
{
    my ( $db, $url ) = @_;

    Readonly my $treat_fragment_as_path => 1;
    my $all_urls = [ MediaWords::Util::URL::all_url_variants( $db, $url, $treat_fragment_as_path ) ];

    my $ua = MediaWords::Util::Web::UserAgentDetermined();
    $ua->timing( '1,3,15,60,300,600' );

    my $url_counts = {};
    for my $u ( @{ $all_urls } )
    {
        my $count = _get_single_url_tweet_count( $ua, $u );
        $url_counts->{ $count } = $u;
    }

    return List::Util::sum( keys( %{ $url_counts } ) );
}

sub get_and_store_tweet_count
{
    my ( $db, $story ) = @_;

    my $count;
    eval { $count = get_url_tweet_count( $db, $story->{ url } ); };
    my $error = $@ ? $@ : undef;
    $count ||= 0;

    $db->query( <<END, $story->{ stories_id }, $count, $error );
with try_update as (
  update story_statistics 
        set twitter_url_tweet_count = \$2, twitter_url_tweet_count_error = \$3
        where stories_id = \$1
        returning *
)
insert into story_statistics ( stories_id, twitter_url_tweet_count, twitter_url_tweet_count_error )
    select \$1, \$2, \$3
        where not exists ( select * from try_update );
END

    return $count;

}

1;
