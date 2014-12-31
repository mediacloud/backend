package MediaWords::Util::Twitter;

#
# Twitter API helper
#

use strict;
use warnings;

use URI::Escape;

use MediaWords::Util::JSON;
use MediaWords::Util::URL;
use MediaWords::Util::Web;

sub _get_single_url_tweet_count
{
    my ( $ua, $url ) = @_;

    my $response = $ua->get( 'https://cdn.api.twitter.com/1/urls/count.json?url=' . uri_escape( $url ) );

    if ( !$response->is_success )
    {
        warn( "error fetching tweet count for url '$url'" );
        return 0;
    }
    my $decoded_content = $response->decoded_content;

    my $data = MediaWords::Util::JSON::decode_json( $decoded_content );

    say STDERR "$url: $data->{ count }";

    return $data->{ count };
}

# use cdn.api.twitter.com/1/urls/count.json to get count of tweets referencing the given url, including all variants
# of the url we can figure out
#
# https://cdn.api.twitter.com/1/urls/count.json?url=http://www.theonion.com/articles/how-to-protect-yourself-against-ebola,37085
sub get_url_tweet_count
{
    my ( $db, $url ) = @_;

    my $all_urls = [ MediaWords::Util::URL::all_url_variants( $db, $url ) ];

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

1;
