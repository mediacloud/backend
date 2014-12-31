package MediaWords::Util::Facebook;

#
# Facebook API helper
#

use strict;
use warnings;

use URI::Escape;

use MediaWords::Util::JSON;
use MediaWords::Util::URL;
use MediaWords::Util::Web;

sub _get_single_url_share_count
{
    my ( $ua, $url ) = @_;

    my $response = $ua->get( 'https://graph.facebook.com/?id=' . uri_escape( $url ) );

    if ( !$response->is_success )
    {
        warn( "error fetching for url '$url'" );
        return 0;
    }
    my $decoded_content = $response->decoded_content;

    my $data = MediaWords::Util::JSON::decode_json( $decoded_content );

    my $shares = $data->{ shares } || 0;

    say STDERR "$url: $shares";

    return $shares || 0;
}

# use https://graph.facebook.com/?id= to get number of shares for the given url
# https://graph.facebook.com/?id=http://www.google.com/
sub get_url_share_count
{
    my ( $db, $url ) = @_;

    my $all_urls = [ MediaWords::Util::URL::all_url_variants( $db, $url ) ];

    my $ua = MediaWords::Util::Web::UserAgentDetermined();
    $ua->timing( '1,3,15,60,300,600' );

    my $url_counts = {};
    for my $u ( @{ $all_urls } )
    {
        my $count = _get_single_url_share_count( $ua, $u );
        $url_counts->{ $count } = $u;
    }

    return List::Util::sum( keys( %{ $url_counts } ) );
}

1;
