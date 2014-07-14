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

# From $start_timestamp and $end_timestamp parameters, return API parameters "unit_reference_ts" and "units"
# die()s on error
sub _unit_reference_ts_and_units_from_start_end_timestamps($$$)
{
    my ( $start_timestamp, $end_timestamp, $max_bitly_limit ) = @_;

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
        if ( $delta_days > $max_bitly_limit )
        {
            die "Difference between start_timestamp ($start_timestamp) and end_timestamp ($end_timestamp) " .
              "is bigger than Bit.ly's limit of $max_bitly_limit days.";
        }

        $unit_reference_ts = $end_timestamp;
        $units             = $delta_days;
    }

    $unit_reference_ts .= '';
    $units             .= '';

    return ( $unit_reference_ts, $units );
}

# Returns true if URL is valid for Bit.ly shortening
sub _url_is_valid_for_bitly($)
{
    my $url = shift;

    unless ( $url )
    {
        warn "URL is undefined";
        return 0;
    }

    my $uri = URI->new( $url )->canonical;

    unless ( $uri->scheme )
    {
        warn "Scheme is undefined for URL $url";
        return 0;
    }
    unless ( $uri->scheme eq 'http' or $uri->scheme eq 'https' or $uri->scheme eq 'ftp' )
    {
        warn "Scheme is not HTTP(s) or FTP for URL $url";
        return 0;
    }

    return 1;
}

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
        die 'API returned non-200 HTTP status code ' .
          $json->{ status_code } . '; JSON: ' . $json_string . '; request parameters: ' . Dumper( $params );
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

# Fetch the URL, evaluate HTTP / HTML redirects; return URL and data after all those redirects; die() on error
sub url_and_data_after_redirects($;$$)
{
    my ( $orig_url, $max_http_redirect, $max_meta_redirect ) = @_;

    unless ( _url_is_valid_for_bitly( $orig_url ) )
    {
        die "URL is invalid: $orig_url";
    }

    my $uri = URI->new( $orig_url )->canonical;

    $max_http_redirect //= 7;
    $max_meta_redirect //= 3;

    my $html = undef;

    for ( my $meta_redirect = 1 ; $meta_redirect <= $max_meta_redirect ; ++$meta_redirect )
    {

        # Do HTTP request to the current URL
        my $ua = MediaWords::Util::Web::UserAgent;

        $ua->max_redirect( $max_http_redirect );

        my $response = $ua->get( $uri->as_string );

        unless ( $response->is_success )
        {
            warn "Request to " . $uri->as_string . " was unsuccessful: " . $response->status_line;
            $uri = URI->new( $orig_url )->canonical;
            last;
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
        $html = $response->decoded_content || '';
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

    return ( $uri->as_string, $html );
}

# Canonicalize URL for Bit.ly API lookup; die() on error
sub url_canonical($)
{
    my $url = shift;

    unless ( _url_is_valid_for_bitly( $url ) )
    {
        die "URL is invalid: $url";
    }

    my $uri = URI->new( $url )->canonical;

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

    # Get URL after HTTP / HTML redirects
    my ( $url_after_redirects, $data_after_redirects ) = url_and_data_after_redirects( $url );

    my %urls = (

        # Normal URL (don't touch anything)
        'normal' => $url,

        # Normal URL after redirects
        'after_redirects' => $url_after_redirects,

        # Canonical URL
        'canonical' => url_canonical( $url ),

        # Canonical URL after redirects
        'after_redirects_canonical' => url_canonical( $url_after_redirects )
    );

    # If <link rel="canonical" /> is present, try that one too
    if ( defined $data_after_redirects )
    {
        my $url_link_rel_canonical =
          MediaWords::Util::URL::link_canonical_url_from_html( $data_after_redirects, $url_after_redirects );
        if ( $url_link_rel_canonical )
        {
            say STDERR "Found <link rel=\"canonical\" /> for URL $url_after_redirects " .
              "(original URL: $url): $url_link_rel_canonical";

            $urls{ 'after_redirects_canonical_via_link_rel' } = $url_link_rel_canonical;
        }
    }

    return uniq( values %urls );
}

# Query for a Bitlinks based on a long URL
# (http://dev.bitly.com/links.html#v3_link_lookup)
#
# Params: URLs (arrayref) to query
#
# Returns: hashref with link lookup results, e.g.:
#     {
#         "link_lookup": [
#             {
#                 "aggregate_link": "http://bit.ly/2V6CFi",
#                 "link": "http://bit.ly/zhheQ9",
#                 "url": "http://www.google.com/"
#             },
#             # ...
#         ]
#     };
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

    foreach my $url ( @{ $urls } )
    {
        unless ( _url_is_valid_for_bitly( $url ) )
        {
            die "One of the URLs is invalid: $url";
        }
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

    my ( $unit_reference_ts, $units ) =
      _unit_reference_ts_and_units_from_start_end_timestamps( $start_timestamp, $end_timestamp, $MAX_BITLY_LIMIT );

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

    if ( scalar @{ $result->{ link_clicks } } == $MAX_BITLY_LIMIT )
    {
        warn "Count of returned 'link_clicks' is at the limit ($MAX_BITLY_LIMIT); " .
          "you might want to reduce the scope of your query.";
    }

    return $result;
}

# Query for a list of categories based on Bit.ly URL
# (http://dev.bitly.com/data_apis.html#v3_link_category)
#
# Params:
# * Bit.ly ID (e.g. "QEH44r")
#
# Returns: hashref with categories, e.g.:
#     {
#         "categories": [
#             "Social Media",
#             "Advertising",
#             "Software and Internet",
#             "Technology",
#             "Business"
#         ]
#     };
#
# die()s on error
sub bitly_link_categories($)
{
    my ( $bitly_id ) = @_;

    unless ( $bitly_id )
    {
        die "Bit.ly ID is undefined.";
    }

    my $result = request( '/v3/link/category', { link => "http://bit.ly/$bitly_id" } );

    # Sanity check
    my @expected_keys = qw/ categories /;
    foreach my $expected_key ( @expected_keys )
    {
        unless ( exists $result->{ $expected_key } )
        {
            die "Result doesn't contain expected '$expected_key' key: " . Dumper( $result );
        }
    }

    unless ( ref( $result->{ categories } ) eq ref( [] ) )
    {
        die "'categories' value is not an arrayref.";
    }

    return $result;
}

# Query for list of referrers based on Bit.ly URL
# (http://dev.bitly.com/link_metrics.html#v3_link_referrers)
#
# Params:
# * Bit.ly ID (e.g. "QEH44r")
# * (optional) starting timestamp for which to query statistics
# * (optional) ending timestamp for which to query statistics
#
# Returns: hashref with list of referrers (plus "unit_reference_ts" value), e.g.:
#     {
#         "referrers": [
#             {
#                 "clicks": 1129,
#                 "referrer": "direct"
#             },
#             {
#                 "clicks": 55,
#                 "referrer": "http://news.ycombinator.com/item"
#             },
#             {
#                 "clicks": 41,
#                 "referrer": "http://twitter.com/"
#             },
#             {
#                 "clicks": 25,
#                 "referrer": "yxG0tQXMY40="
#             },
#             {
#                 "clicks": 24,
#                 "referrer": "http://localhost/www/2ii.jp/ii.php"
#             }
#         ],
#         "tz_offset": -5,
#         "unit": "day",
#         "unit_reference_ts": 1360351157,
#         "units": -1
#     };
#
# die()s on error
sub bitly_link_referrers($;$$)
{
    my ( $bitly_id, $start_timestamp, $end_timestamp ) = @_;

    Readonly my $MAX_BITLY_LIMIT => 1000;    # in "/v3/link/referrers" case

    unless ( $bitly_id )
    {
        die "Bit.ly ID is undefined.";
    }

    my ( $unit_reference_ts, $units ) =
      _unit_reference_ts_and_units_from_start_end_timestamps( $start_timestamp, $end_timestamp, $MAX_BITLY_LIMIT );

    my $result = request(
        '/v3/link/referrers',
        {
            link     => "http://bit.ly/$bitly_id",
            limit    => $MAX_BITLY_LIMIT + 0,        # biggest possible limit
            unit     => 'day',                       # daily stats
            timezone => 'Etc/GMT',                   # GMT timestamps

            unit_reference_ts => $unit_reference_ts,
            units             => $units,
        }
    );

    # Sanity check
    my @expected_keys = qw/referrers tz_offset unit units/;
    foreach my $expected_key ( @expected_keys )
    {
        unless ( exists $result->{ $expected_key } )
        {
            die "Result doesn't contain expected '$expected_key' key: " . Dumper( $result );
        }
    }

    unless ( ref( $result->{ referrers } ) eq ref( [] ) )
    {
        die "'referrers' value is not an arrayref.";
    }

    if ( scalar @{ $result->{ referrers } } == $MAX_BITLY_LIMIT )
    {
        warn "Count of returned 'referrers' is at the limit ($MAX_BITLY_LIMIT); " .
          "you might want to reduce the scope of your query.";
    }

    unless ( exists $result->{ unit_reference_ts } )
    {
        # It's not in the API spec, so we add it manually
        $result->{ unit_reference_ts } = ( $unit_reference_ts eq 'now' ? undef : $unit_reference_ts + 0 );
    }

    return $result;
}

# Query for list of shares based on Bit.ly URL
# (http://dev.bitly.com/link_metrics.html#v3_link_shares)
#
# Params:
# * Bit.ly ID (e.g. "QEH44r")
# * (optional) starting timestamp for which to query statistics
# * (optional) ending timestamp for which to query statistics
#
# Returns: hashref with list of shares, e.g.:
#     {
#         "shares": [
#             {
#                 "share_type": "tw",
#                 "shares": 1
#             }
#         ],
#         "total_shares": 1,
#         "tz_offset": -4,
#         "unit": "day",
#         "unit_reference_ts": null,
#         "units": -1
#     };
#
# die()s on error
sub bitly_link_shares($;$$)
{
    my ( $bitly_id, $start_timestamp, $end_timestamp ) = @_;

    Readonly my $MAX_BITLY_LIMIT => 1000;    # in "/v3/link/referrers" case

    unless ( $bitly_id )
    {
        die "Bit.ly ID is undefined.";
    }

    my ( $unit_reference_ts, $units ) =
      _unit_reference_ts_and_units_from_start_end_timestamps( $start_timestamp, $end_timestamp, $MAX_BITLY_LIMIT );

    my $result = request(
        '/v3/link/shares',
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
    my @expected_keys = qw/shares total_shares tz_offset unit unit_reference_ts units/;
    foreach my $expected_key ( @expected_keys )
    {
        unless ( exists $result->{ $expected_key } )
        {
            die "Result doesn't contain expected '$expected_key' key: " . Dumper( $result );
        }
    }

    unless ( ref( $result->{ shares } ) eq ref( [] ) )
    {
        die "'shares' value is not an arrayref.";
    }

    if ( scalar @{ $result->{ shares } } == $MAX_BITLY_LIMIT )
    {
        warn "Count of returned 'shares' is at the limit ($MAX_BITLY_LIMIT); " .
          "you might want to reduce the scope of your query.";
    }

    return $result;
}

1;
