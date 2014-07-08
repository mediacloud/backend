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
use URI;
use URI::QueryParam;
use JSON;
use List::MoreUtils qw/uniq/;
use Scalar::Util qw/looks_like_number/;
use DateTime;
use DateTime::Duration;

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
    foreach my $params_key ( keys %{ $params } )
    {
        $uri->query_param( $params_key => $params->{ $params_key } );
    }
    $uri->query_param( $params );
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

        # if ( scalar @redirects )
        # {
        #     say STDERR "Redirects:";
        #     foreach my $redirect ( @redirects )
        #     {
        #         say STDERR "* From:";
        #         say STDERR "    " . $redirect->request()->uri()->canonical;
        #         say STDERR "  to:";
        #         say STDERR "    " . $redirect->header( 'Location' );
        #     }
        # }

        my $new_uri = $response->request()->uri()->canonical;
        unless ( $uri->eq( $new_uri ) )
        {
            # say STDERR "New URI: " . $new_uri->as_string;
            $uri = $new_uri;
        }

        # Check if the returned document contains <meta http-equiv="refresh" />
        my $html = $response->decoded_content || '';
        my $url_after_meta_redirect = MediaWords::Util::URL::meta_refresh_url_from_html( $html, $uri->as_string );
        if ( $url_after_meta_redirect and $uri->as_string ne $url_after_meta_redirect )
        {
            # say STDERR "URL after <meta /> refresh: $url_after_meta_redirect";
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

# Canonicalize URL for Bit.ly API lookup; die() on error
sub url_canonical($)
{
    my $url = shift;

    unless ( $url )
    {
        die "URL is undefined";
    }

    my $uri = URI->new( $url )->canonical;

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

    # metrika.yandex.ru parameters
    @parameters_to_remove = ( @parameters_to_remove, qw/ yclid _openstat / );

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

    if ( $uri->host =~ /livejournal\.com$/i )
    {
        # Additional parameters specifically for the livejournal.com host
        @parameters_to_remove = ( @parameters_to_remove, qw/ thread nojs / );
    }

    # Some other parameters (common for tracking session IDs, advertising, etc.)
    @parameters_to_remove = (
        @parameters_to_remove,
        qw/ PHPSESSID PHPSESSIONID
          cid s_cid sid ncid ir
          ref oref eref
          ns_mchannel ns_campaign
          wprss custom_click source
          feedName feedType /
    );

    # Make the sorting default (e.g. on Reddit)
    # Some other parameters (common for tracking session IDs, advertising, etc.)
    push( @parameters_to_remove, 'sort' );

    # Delete the "empty" parameter (e.g. in http://www-nc.nytimes.com/2011/06/29/us/politics/29marriage.html?=_r%3D6)
    push( @parameters_to_remove, '' );

    # Remove cruft parameters
    foreach my $parameter ( @parameters_to_remove )
    {
        $uri->query_param_delete( $parameter );
    }

    # Remove parameters that start with '_' (e.g. '_cid') because they're more likely to be the tracking codes
    my @parameters = $uri->query_param;
    foreach my $parameter ( @parameters )
    {
        if ( $parameter =~ /^_/ )
        {
            $uri->query_param_delete( $parameter );
        }
    }

    # FIXME fetch the page, look for <link rel="canonical" />

    return $uri->as_string;
}

# Return all URL variants for all URL to be requested to Bit.ly API:
# 1) Normal URL
# 2) URL after redirects (i.e., fetch the URL, see if it gets redirected somewhere)
# 3) Canonical URL (after removing #fragments, session IDs, tracking parameters, etc.)
# 4) Canonical URL after redirects (do the redirect check first, then strip the tracking parameters from the URL)
sub all_url_variants($)
{
    my $url = shift;

    my %urls = (

        # Normal URL (don't touch anything)
        'normal' => $url,

        # Normal URL after redirects
        'after_redirects' => MediaWords::Util::Bitly::url_after_redirects( $url ),
    );

    # Canonical URL
    $urls{ 'canonical' } = MediaWords::Util::Bitly::url_canonical( $urls{ 'normal' } );

    # Canonical URL after redirects
    $urls{ 'after_redirects_canonical' } = MediaWords::Util::Bitly::url_canonical( $urls{ 'after_redirects' } );

    return uniq( values %urls );
}

# Query for a Bitlinks based on a long URL
# (http://dev.bitly.com/links.html#v3_link_lookup)
#
# Params: URLs (arrayref) to query
#
# Returns: hashref with link lookup results, e.g.:
#     "link_lookup": [
#         {
#             "aggregate_link": "http://bit.ly/2V6CFi",
#             "link": "http://bit.ly/zhheQ9",
#             "url": "http://www.google.com/"
#         },
#         # ...
#     ]
#
# die()s on error
sub bitly_link_lookup($)
{
    my $urls = shift;

    unless ( $urls )
    {
        die "URLs is undefined.";
    }
    unless ( ref( $urls ) eq ref( [] ) )
    {
        die "URLs is not an arrayref.";
    }

    my $result = request( '/v3/link/lookup', { url => $urls } );

    # Sanity check
    my @expected_keys = qw/ link_lookup /;
    foreach my $expected_key ( @expected_keys )
    {
        unless ( exists $result->{ $expected_key } )
        {
            die "Result doesn't contain expected '$expected_key' key: " . Dumper( $result );
        }
    }

    unless ( ref( $result->{ link_lookup } ) eq ref( [] ) )
    {
        die "'link_lookup' value is not an arrayref.";
    }
    unless ( scalar @{ $result->{ link_lookup } } == scalar( @{ $urls } ) )
    {
        die "The number of URLs returned differs from the number of input URLs.";
    }

    return $result;
}

# Query for a Bitlinks based on a long URL
# (http://dev.bitly.com/links.html#v3_link_lookup); try multiple variants
# (normal, canonical, before redirects, after redirects)
#
# Params: URL to query
#
# Returns: hashref with "URL => Bit.ly ID" pairs, e.g.:
#     {
#         'http://www.foxnews.com/us/2013/07/04/crowds-across-america-protest-nsa-in-restore-fourth-movement/' => '14VhXAj',
#         'http://feeds.foxnews.com/~r/foxnews/national/~3/bmilmNKlhLw/' => undef,
#         'http://www.foxnews.com/us/2013/07/04/crowds-across-america-protest-nsa-in-restore-fourth-movement/?utm_source=
#              feedburner&utm_medium=feed&utm_campaign=Feed%3A+foxnews%2Fnational+(Internal+-+US+Latest+-+Text)' => undef
#     };
#
# die()s on error
sub bitly_link_lookup_all_variants($)
{
    my $url = shift;

    my @urls = all_url_variants( $url );
    unless ( scalar @urls )
    {
        die "No URLs returned for URL $url";
    }

    my $result = bitly_link_lookup( \@urls );

    my %bitly_link_lookup;
    foreach my $link_lookup ( @{ $result->{ link_lookup } } )
    {
        unless ( ref( $link_lookup ) eq ref( {} ) )
        {
            die "Link lookup result is not a hashref.";
        }

        my $link_lookup_url = $link_lookup->{ url };
        unless ( $link_lookup_url )
        {
            die "Link lookup URL is empty.";
        }

        my $link_lookup_aggregate_id;
        if ( $link_lookup->{ aggregate_link } )
        {

            my $aggregate_link_uri = URI->new( $link_lookup->{ aggregate_link } );
            $link_lookup_aggregate_id = $aggregate_link_uri->path;
            $link_lookup_aggregate_id =~ s|^/||;
        }
        else
        {
            if ( $link_lookup->{ error } )
            {
                if ( uc( $link_lookup->{ error } ) eq 'NOT_FOUND' )
                {
                    $link_lookup_aggregate_id = undef;
                }
                else
                {
                    die "'error' is not 'NOT_FOUND': " . $link_lookup->{ error };
                }
            }
            else
            {
                die "No 'aggregate_link' was provided, but it's not an API error either.";
            }
        }

        $bitly_link_lookup{ $link_lookup_url } = $link_lookup_aggregate_id;
    }

    return \%bitly_link_lookup;
}

# Query for number of link clicks based on Bit.ly URL
# (http://dev.bitly.com/link_metrics.html#v3_link_clicks)
#
# Params:
# * Bit.ly ID (e.g. "QEH44r")
# * (optional) starting timestamp for which to query statistics
# * (optional) ending timestamp for which to query statistics
#
# Returns: hashref with click statistics, e.g.:
#     {
#         "link_clicks": [
#             {
#                 "clicks": 1,
#                 "dt": 1360299600
#             },
#             {
#                 "clicks": 2,
#                 "dt": 1360213200
#             },
#             {
#                 "clicks": 2,
#                 "dt": 1360126800
#             },
#             {
#                 "clicks": 3,
#                 "dt": 1360040400
#             },
#             {
#                 "clicks": 10,
#                 "dt": 1359954000
#             }
#         ],
#         "tz_offset": -5,
#         "unit": "day",
#         "unit_reference_ts": 1360351157,
#         "units": 5
#     };
#
# die()s on error
sub bitly_link_clicks($;$$)
{
    my ( $bitly_id, $start_timestamp, $end_timestamp ) = @_;

    Readonly my $MAX_BITLY_LIMIT => 1000;    # in "/v3/link/clicks" case

    unless ( $bitly_id )
    {
        die "Bit.ly ID is undefined.";
    }

    # Both or none must be defined (note "xor")
    if ( defined $start_timestamp xor defined $end_timestamp )
    {
        die "Both (or none) start_timestamp and end_timestamp must be defined.";
    }
    else
    {

        if ( defined $start_timestamp and defined $end_timestamp )
        {

            unless ( looks_like_number( $start_timestamp ) )
            {
                die "start_timestamp is not a timestamp.";
            }
            unless ( looks_like_number( $end_timestamp ) )
            {
                die "end_timestamp is not a timestamp.";
            }

            if ( $start_timestamp > $end_timestamp )
            {
                die "start_timestamp is bigger than end_timestamp.";
            }

        }
    }

    my $unit_reference_ts = 'now';
    my $units             = '-1';

    if ( defined $start_timestamp and defined $end_timestamp )
    {

        my $start_date = DateTime->from_epoch( epoch => $start_timestamp, time_zone => 'Etc/GMT' );
        my $end_date   = DateTime->from_epoch( epoch => $end_timestamp,   time_zone => 'Etc/GMT' );

        # Round timestamps to the nearest day
        $start_date->set( hour => 0, minute => 0, second => 0 );
        $end_date->set( hour => 0, minute => 0, second => 0 );

        my $delta      = $end_date->delta_days( $start_date );
        my $delta_days = $delta->delta_days;
        say STDERR "Delta days between $start_timestamp and $end_timestamp: $delta_days";

        if ( $delta_days == 0 )
        {
            say STDERR "Delta days between $start_timestamp and $end_timestamp is 0, so setting it to 1";
            $delta_days = 1;
        }

        # Make sure it doesn't exceed Bit.ly's limit
        if ( $delta_days > $MAX_BITLY_LIMIT )
        {
            die "Difference between start_timestamp ($start_timestamp) and end_timestamp ($end_timestamp) " .
              "is bigger than Bit.ly's limit of $MAX_BITLY_LIMIT days.";
        }

        $unit_reference_ts = $end_timestamp;
        $units             = $delta_days;
    }

    my $result = request(
        '/v3/link/clicks',
        {
            link     => "http://bit.ly/$bitly_id",
            limit    => $MAX_BITLY_LIMIT + 0,        # biggest possible limit
            rollup   => 'false',                     # detailed stats for the whole period
            unit     => 'day',                       # daily stats
            timezone => 'Etc/GMT',                   # GMT timestamps

            unit_reference_ts => $unit_reference_ts,
            units             => $units,
        }
    );

    # Sanity check
    my @expected_keys = qw/link_clicks tz_offset unit unit_reference_ts units/;
    foreach my $expected_key ( @expected_keys )
    {
        unless ( exists $result->{ $expected_key } )
        {
            die "Result doesn't contain expected '$expected_key' key: " . Dumper( $result );
        }
    }

    unless ( ref( $result->{ link_clicks } ) eq ref( [] ) )
    {
        die "'link_clicks' value is not an arrayref.";
    }

    return $result;
}

1;
