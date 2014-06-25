package MediaWords::Util::Bitly;

#
# Bit.ly API helper
#

use strict;
use warnings;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Util::Web;
use MediaWords::Util::Config;
use JSON;

use constant BITLY_API_ENDPOINT => 'https://api-ssl.bitly.com/';

# Sends a request to Bit.ly API, returns a 'data' key hashref with results; die()s on error
sub request($$)
{
    my ( $path, $params ) = @_;

    unless ( $path )
    {
        die "Path is null; should be something like '/v3/link/lookup'";
    }
    unless ( $params )
    {
        die "Parameters argument is null; should be hashref of API call parameters";
    }
    unless ( ref( $params ) eq ref( {} ) )
    {
        die "Parameters argument is not a hashref.";
    }

    # Add access token
    my $config       = MediaWords::Util::Config::get_config;
    my $access_token = $config->{ bitly }->{ access_token };
    unless ( $access_token )
    {
        die "Bit.ly Generic Access Token is not set in the configuration";
    }
    if ( $params->{ access_token } )
    {
        die "Access token is already set; not resetting to the one from configuration";
    }
    $params->{ access_token } = $access_token;

    my $uri = URI->new( BITLY_API_ENDPOINT );
    $uri->path( $path );
    $uri->query_form( $params );
    my $url = $uri->as_string;

    my $ua       = MediaWords::Util::Web::UserAgent;
    my $response = $ua->get( $url );

    unless ( $response->is_success )
    {
        die "Error while fetching API response: " . $response->status_line . "; URL: $url";
    }

    my $json_string = $response->decoded_content;

    my $json;
    eval { $json = decode_json( $json_string ); };
    if ( $@ or ( !$json ) )
    {
        die "Unable to decode JSON response: $@; JSON: $json_string";
    }
    unless ( ref( $json ) eq ref( {} ) )
    {
        die "JSON response is not a hashref; JSON: $json_string";
    }

    if ( $json->{ status_code } != 200 )
    {
        die "API returned non-200 HTTP status code " . $json->{ status_code } . "; JSON: $json_string";
    }

    my $json_data = $json->{ data };
    unless ( $json_data )
    {
        die "JSON 'data' key is undef; JSON: $json_string";
    }
    unless ( ref( $json_data ) eq ref( {} ) )
    {
        die "JSON 'data' key is not a hashref; JSON: $json_string";
    }

    return $json_data;
}

# Canonicalizes URL for Bit.ly API lookup; die()s on error
sub canonicalize_url($)
{
    my $url = shift;

    unless ( $url )
    {
        die "URL is undefined";
    }

    my $uri = URI->new_abs( $url, 'http' )->canonical;

    unless ( $uri->scheme )
    {
        die "Scheme is undefined for URL $url";
    }
    unless ( $uri->scheme eq 'http' or $uri->scheme eq 'https' )
    {
        die "Scheme is not HTTP(s) for URL $url";
    }

    # Remove #fragment
    $uri->fragment( undef );

    my %query_form = $uri->query_form;

    # Remove GA parameters (https://support.google.com/analytics/answer/1033867?hl=en)
    delete $query_form{ utm_source };
    delete $query_form{ utm_medium };
    delete $query_form{ utm_term };
    delete $query_form{ utm_content };
    delete $query_form{ utm_campaign };
    delete $query_form{ utm_reader };
    delete $query_form{ utm_place };
    delete $query_form{ ga_source };
    delete $query_form{ ga_medium };
    delete $query_form{ ga_term };
    delete $query_form{ ga_content };
    delete $query_form{ ga_campaign };
    delete $query_form{ ga_place };

    # Remove Facebook parameters (https://developers.facebook.com/docs/games/canvas/referral-tracking)
    delete $query_form{ fb_action_ids };
    delete $query_form{ fb_action_types };
    delete $query_form{ fb_source };
    delete $query_form{ fb_ref };
    delete $query_form{ action_object_map };
    delete $query_form{ action_type_map };
    delete $query_form{ action_ref_map };

    if ( $uri->host =~ /facebook\.com$/i )
    {
        delete $query_form{ ref };
        delete $query_form{ fref };
        delete $query_form{ hc_location };
    }

    if ( $uri->host =~ /nytimes\.com$/i ) {
        delete $query_form{ emc };
        delete $query_form{ partner };
        delete $query_form{ _r };
        delete $query_form{ hp };
        delete $query_form{ inline };
    }

    # Remove metrika.yandex.ru parameters
    delete $query_form{ yclid };
    delete $query_form{ _openstat };

    # Remove some other parameters
    delete $query_form{ PHPSESSID };
    delete $query_form{ s_cid };
    delete $query_form{ sid };
    delete $query_form{ ncid };
    delete $query_form{ wprss };
    delete $query_form{ fsrc };
    delete $query_form{ custom_click };
    delete $query_form{ ns_mchannel };
    delete $query_form{ ns_campaign };
    delete $query_form{ source };
    delete $query_form{ ref };
    delete $query_form{ oref };
    delete $query_form{ eref };

    # Make the sorting default (e.g. on Reddit)
    delete $query_form{ sort };

    $uri->query_form( \%query_form );

    # FIXME remove parameters that contain URLs
    # FIXME remove base64-encoded parameters (likely to be tracking codes)
    # FIXME try fetching an URL, use the first redirect as the real URL
    # FIXME fetch the page, look for <link rel="canonical" />

    return $uri->as_string;
}

1;
