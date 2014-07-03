package MediaWords::Util::Bitly;

#
# Bit.ly API helper
#

use strict;
use warnings;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Util::Web;
use MediaWords::Util::URL;
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
# Fetch the URL, evaluate HTTP / HTML redirects, and return URL after all those redirects; die() on error
sub url_after_redirects($;$$)
{
    my ( $orig_url, $max_http_redirect, $max_meta_redirect ) = @_;

    unless ( $orig_url )
    {
        die "URL is undefined";
    }

    my $uri = URI->new( $orig_url )->canonical;

    unless ( $uri->scheme )
    {
        die "Scheme is undefined for URL $orig_url";
    }
    unless ( $uri->scheme eq 'http' or $uri->scheme eq 'https' )
    {
        die "Scheme is not HTTP(s) for URL $orig_url";
    }

    $max_http_redirect //= 7;
    $max_meta_redirect //= 3;

    for ( my $meta_redirect = 1 ; $meta_redirect <= $max_meta_redirect ; ++$meta_redirect )
    {

        # Do HTTP request to the current URL
        my $ua = MediaWords::Util::Web::UserAgent;

        $ua->max_redirect( $max_http_redirect );

        my $response = $ua->get( $uri->as_string );

        unless ( $response->is_success )
        {
            warn "Request to " . $uri->as_string . " was unsuccessful: " . $response->status_line;
            return $orig_url;
        }

        my @redirects = $response->redirects();
        if ( scalar @redirects )
        {
            say STDERR "Redirects:";
            foreach my $redirect ( @redirects )
            {
                say STDERR "* From:";
                say STDERR "    " . $redirect->request()->uri()->canonical;
                say STDERR "  to:";
                say STDERR "    " . $redirect->header( 'Location' );
            }
        }

        my $new_uri = $response->request()->uri()->canonical;
        unless ( $uri->eq( $new_uri ) )
        {
            say STDERR "New URI: " . $new_uri->as_string;
            $uri = $new_uri;
        }

        # Check if the returned document contains <meta http-equiv="refresh" />
        my $html = $response->decoded_content || '';
        my $url_after_meta_redirect = MediaWords::Util::URL::meta_refresh_url_from_html( $html );
        if ( $url_after_meta_redirect and $uri->as_string ne $url_after_meta_redirect )
        {
            say STDERR "URL after <meta /> refresh: $url_after_meta_redirect";
            $uri = URI->new( $url_after_meta_redirect )->canonical;

            # ...and repeat the HTTP redirect cycle here
        }
        else
        {
            # No <meta /> refresh, the current URL is the final one
            last;
        }

    }

    return $uri->as_string;
}
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

    # FIXME fetch the page, look for <link rel="canonical" />

    return $uri->as_string;
}

1;
