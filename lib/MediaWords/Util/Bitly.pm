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

    my @parameters_to_remove;

    # GA parameters (https://support.google.com/analytics/answer/1033867?hl=en)
    @parameters_to_remove = (
        @parameters_to_remove,
        qw/ utm_source utm_medium utm_term utm_content utm_campaign utm_reader utm_place
          ga_source ga_medium ga_term ga_content ga_campaign ga_place /
    );

    # Facebook parameters (https://developers.facebook.com/docs/games/canvas/referral-tracking)
    @parameters_to_remove = (
        @parameters_to_remove,
        qw/ fb_action_ids fb_action_types fb_source fb_ref
          action_object_map action_type_map action_ref_map
          fsrc /
    );

    if ( $uri->host =~ /facebook\.com$/i )
    {
        # Additional parameters specifically for the facebook.com host
        @parameters_to_remove = ( @parameters_to_remove, qw/ ref fref hc_location / );
    }

    if ( $uri->host =~ /nytimes\.com$/i )
    {
        # Additional parameters specifically for the nytimes.com host
        @parameters_to_remove = ( @parameters_to_remove, qw/ emc partner _r hp inline / );
    }

    # metrika.yandex.ru parameters
    @parameters_to_remove = ( @parameters_to_remove, qw/ yclid _openstat / );

    # Some other parameters (common for tracking session IDs, advertising, etc.)
    @parameters_to_remove = (
        @parameters_to_remove,
        qw/ PHPSESSID PHPSESSIONID
          s_cid sid ncid
          ref oref eref
          ns_mchannel ns_campaign
          wprss custom_click source /
    );

    # Make the sorting default (e.g. on Reddit)
    # Some other parameters (common for tracking session IDs, advertising, etc.)
    push( @parameters_to_remove, 'sort' );

    my %query_form = $uri->query_form;
    foreach my $parameter ( @parameters_to_remove )
    {
        delete $query_form{ $parameter };
    }
    $uri->query_form( \%query_form );

    # FIXME remove parameters that contain URLs
    # FIXME remove base64-encoded parameters (likely to be tracking codes)
    # FIXME try fetching an URL, use the first redirect as the real URL
    # FIXME fetch the page, look for <link rel="canonical" />

    return $uri->as_string;
}

1;
