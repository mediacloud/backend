package MediaWords::Util::Bitly;

#
# Bit.ly API helper
#

use strict;
use warnings;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Util::Process;
use MediaWords::Util::Web;
use MediaWords::Util::URL;
use MediaWords::Util::Config;
use MediaWords::Util::JSON;
use MediaWords::KeyValueStore::GridFS;
use URI;
use URI::QueryParam;
use JSON;
use Scalar::Util qw/looks_like_number/;
use Scalar::Defer;
use DateTime;
use DateTime::Duration;

use constant BITLY_API_ENDPOINT => 'https://api-ssl.bitly.com/';

# (Lazy-initialized) Bit.ly access token
my $_bitly_access_token = lazy
{
    unless ( bitly_processing_is_enabled() )
    {
        fatal_error( "Bit.ly processing is not enabled; why are you accessing this variable?" );
    }

    my $config = MediaWords::Util::Config->get_config();

    my $access_token = $config->{ bitly }->{ access_token };
    unless ( $access_token )
    {
        die "Unable to determine Bit.ly access token.";
    }

    return $access_token;
};

# (Lazy-initialized) Bit.ly timeout
my $_bitly_timeout = lazy
{
    unless ( bitly_processing_is_enabled() )
    {
        fatal_error( "Bit.ly processing is not enabled; why are you accessing this variable?" );
    }

    my $config = MediaWords::Util::Config->get_config();

    my $timeout = $config->{ bitly }->{ timeout };
    unless ( $timeout )
    {
        die "Unable to determine Bit.ly timeout.";
    }

    return $timeout;
};

# (Lazy-initialized) MongoDB GridFS key-value store
# We use a static, package-wide variable here because:
# a) MongoDB handler should support being used by multiple threads by now, and
# b) each Gearman worker is a separate process so there shouldn't be any resource clashes.
my $_gridfs_store = lazy
{
    unless ( MediaWords::Util::Bitly::bitly_processing_is_enabled() )
    {
        fatal_error( "Bit.ly processing is not enabled; why are you accessing this variable?" );
    }

    my $config = MediaWords::Util::Config->get_config();

    # GridFS storage
    my $gridfs_database_name = $config->{ mongodb_gridfs }->{ bitly }->{ database_name };
    unless ( $gridfs_database_name )
    {
        fatal_error( "CoreNLP annotator is enabled, but MongoDB GridFS database name is not set." );
    }

    my $gridfs_store = MediaWords::KeyValueStore::GridFS->new( { database_name => $gridfs_database_name } );
    say STDERR "Will write CoreNLP annotator results to GridFS database: $gridfs_database_name";

    return $gridfs_store;
};

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

# Returns true if Bit.ly processing is enabled
sub bitly_processing_is_enabled()
{
    my $config = MediaWords::Util::Config->get_config();
    my $bitly_enabled = $config->{ bitly }->{ enabled } // '';

    if ( $bitly_enabled eq 'yes' )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Sends a request to Bit.ly API, returns a 'data' key hashref with results; die()s on error
sub request($$)
{
    my ( $path, $params ) = @_;

    unless ( bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

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
    if ( $params->{ access_token } )
    {
        die "Access token is already set; not resetting to the one from configuration";
    }
    $params->{ access_token } = $_bitly_access_token;

    my $uri = URI->new( BITLY_API_ENDPOINT );
    $uri->path( $path );
    foreach my $params_key ( keys %{ $params } )
    {
        $uri->query_param( $params_key => $params->{ $params_key } );
    }
    $uri->query_param( $params );
    my $url = $uri->as_string;

    my $ua = MediaWords::Util::Web::UserAgent;
    $ua->timeout( $_bitly_timeout );
    $ua->max_size( undef );

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
        # Rate limit exceeded
        if ( $json->{ status_code } == 403 and $json->{ status_txt } eq 'RATE_LIMIT_EXCEEDED' )
        {
            die 'Bit.ly rate limit exceeded. Please wait for a bit and try again.';

        }
        else
        {
            die 'API returned non-200 HTTP status code ' .
              $json->{ status_code } . '; JSON: ' . $json_string . '; request parameters: ' . Dumper( $params );

        }
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

# Query for a Bitlink information based on a Bit.ly IDs
# (http://dev.bitly.com/links.html#v3_info)
#
# Not to be confused with /v3/link/info (http://dev.bitly.com/data_apis.html#v3_link_info)!
#
# Params: Bit.ly IDs (arrayref) to query, e.g. ["1RmnUT"]
#
# Returns: hashref with link info results, e.g.:
#     {
#         "info": [
#             {
#                 "hash": "1RmnUT",
#                 "title": null,
#                 "created_at": 1212926400,
#                 "created_by": "bitly",
#                 "global_hash": "1RmnUT",
#                 "user_hash": "1RmnUT"
#             },
#             // ...
#         ]
#     };
#
# die()s on error
sub bitly_info($)
{
    my $bitly_ids = shift;

    unless ( bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    unless ( $bitly_ids )
    {
        die "Bit.ly IDs is undefined.";
    }
    unless ( ref( $bitly_ids ) eq ref( [] ) )
    {
        die "Bit.ly IDs is not an arrayref.";
    }
    unless ( scalar( @{ $bitly_ids } ) )
    {
        die "Bit.ly IDs arrayref is empty.";
    }

    my $result = request( '/v3/info', { hash => $bitly_ids, expand_user => 'false' } );

    # Sanity check
    my @expected_keys = qw/ info /;
    foreach my $expected_key ( @expected_keys )
    {
        unless ( exists $result->{ $expected_key } )
        {
            die "Result doesn't contain expected '$expected_key' key: " . Dumper( $result );
        }
    }

    unless ( ref( $result->{ info } ) eq ref( [] ) )
    {
        die "'info' value is not an arrayref.";
    }
    unless ( scalar @{ $result->{ info } } == scalar( @{ $bitly_ids } ) )
    {
        die "The number of results returned differs from the number of input Bit.ly IDs.";
    }

    foreach my $info_item ( @{ $result->{ info } } )
    {
        # Note that "short_url" is not being returned (although it's in the API spec)
        @expected_keys = qw/ created_at created_by global_hash title user_hash /;

        foreach my $expected_key ( @expected_keys )
        {
            unless ( exists $info_item->{ $expected_key } )
            {
                die "Result item doesn't contain expected '$expected_key' key: " . Dumper( $info_item );
            }
        }
    }

    return $result;
}

# Query for a Bitlink information based on a Bit.ly IDs
# (http://dev.bitly.com/links.html#v3_info)
#
# Not to be confused with /v3/link/info (http://dev.bitly.com/data_apis.html#v3_link_info)!
#
# Params: Bit.ly IDs (arrayref) to query, e.g. ["1RmnUT"]
#
# Returns: hashref with "Bit.ly ID => link info" pairs, e.g.:
#     {
#         "1RmnUT": {
#             "hash": "1RmnUT",
#             "title": null,
#             "created_at": 1212926400,
#             "created_by": "bitly",
#             "global_hash": "1RmnUT",
#             "user_hash": "1RmnUT"
#         },
#         "RmnUT" : undef,
#         # ...
#     };
#
# die()s on error
sub bitly_info_hashref($)
{
    my $bitly_ids = shift;

    unless ( bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    unless ( $bitly_ids )
    {
        die "Bit.ly IDs is undefined.";
    }
    unless ( ref( $bitly_ids ) eq ref( [] ) )
    {
        die "Bit.ly IDs is not an arrayref.";
    }
    unless ( scalar( @{ $bitly_ids } ) )
    {
        die "Bit.ly IDs arrayref is empty.";
    }

    my $result = bitly_info( $bitly_ids );

    my %bitly_info;
    foreach my $info ( @{ $result->{ info } } )
    {
        unless ( ref( $info ) eq ref( {} ) )
        {
            die "Info result is not a hashref.";
        }

        my $info_bitly_id = $info->{ hash };
        unless ( $info_bitly_id )
        {
            die "Bit.ly ID is empty.";
        }

        if ( $info->{ error } )
        {
            if ( uc( $info->{ error } ) eq 'NOT_FOUND' )
            {
                $info = undef;
            }
            else
            {
                die "'error' is not 'NOT_FOUND': " . $info->{ error };
            }
        }

        $bitly_info{ $info_bitly_id } = $info;
    }

    return \%bitly_info;
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

    unless ( bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

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
        unless ( MediaWords::Util::URL::is_http_url( $url ) )
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

    foreach my $link_lookup_item ( @{ $result->{ link_lookup } } )
    {
        @expected_keys = qw/ aggregate_link url /;

        foreach my $expected_key ( @expected_keys )
        {
            unless ( exists $link_lookup_item->{ $expected_key } )
            {
                die "Result item doesn't contain expected '$expected_key' key: " . Dumper( $link_lookup_item );
            }
        }
    }

    return $result;
}

# Query for a Bitlinks based on a long URL
# (http://dev.bitly.com/links.html#v3_link_lookup)
#
# Params: URLs (arrayref) to query
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
sub bitly_link_lookup_hashref($)
{
    my $urls = shift;

    unless ( bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    unless ( $urls )
    {
        die "URLs is not a hashref.";
    }

    unless ( scalar @{ $urls } )
    {
        die "No URLs.";
    }

    my $result = bitly_link_lookup( $urls );

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
sub bitly_link_lookup_hashref_all_variants($)
{
    my $url = shift;

    unless ( bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    my @urls = MediaWords::Util::URL::all_url_variants( $url );
    unless ( scalar @urls )
    {
        die "No URLs returned for URL $url";
    }

    return bitly_link_lookup_hashref( \@urls );
}

# Query for a list of categories based on Bit.ly URL
# (http://dev.bitly.com/data_apis.html#v3_link_category)
#
# Params:
# * Bit.ly ID (e.g. "QEH44r")
#
# Returns: arrayref of categories, e.g.:
#     [
#         "Social Media",
#         "Advertising",
#         "Software and Internet",
#         "Technology",
#         "Business"
#     ];
#
# die()s on error
sub bitly_link_categories($)
{
    my ( $bitly_id ) = @_;

    unless ( bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

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

    return $result->{ categories };
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

    unless ( bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

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

    unless ( bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

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

    Readonly my $MAX_BITLY_LIMIT => 1000;    # in "/v3/link/shares" case

    unless ( bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

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

{
    # Object to determine what kind of stats to fetch from Bit.ly (used in
    # _fetch_story_stats())
    package MediaWords::Util::Bitly::StatsToFetch;

    sub new($;$$$$)
    {
        my $class = shift;
        my ( $fetch_categories, $fetch_clicks, $fetch_referrers, $fetch_shares ) = @_;

        my $self = {};
        bless $self, $class;

        # Default values
        $self->{ fetch_categories } = $fetch_categories // 0;
        $self->{ fetch_clicks }     = $fetch_clicks     // 1;
        $self->{ fetch_referrers }  = $fetch_referrers  // 1;
        $self->{ fetch_shares }     = $fetch_shares     // 0;

        return $self;
    }

    1;
}

sub fetch_story_stats($$$$;$)
{
    my ( $db, $stories_id, $start_timestamp, $end_timestamp, $stats_to_fetch ) = @_;

    unless ( MediaWords::Util::Bitly::bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    {
        $Data::Dumper::Indent = 0;

        if ( defined $stats_to_fetch )
        {

            unless ( ref( $stats_to_fetch ) eq 'MediaWords::Util::Bitly::StatsToFetch' )
            {
                die "'stats_to_fetch' must be an instance of MediaWords::Util::Bitly::StatsToFetch";
            }

            say STDERR "Will fetch the following Bit.ly stats: " . Dumper( $stats_to_fetch );

        }
        else
        {
            $stats_to_fetch = MediaWords::Util::Bitly::StatsToFetch->new();
            say STDERR "Will fetch default Bit.ly stats: " . Dumper( $stats_to_fetch );
        }

    }

    my $story = $db->find_by_id( 'stories', $stories_id );
    unless ( $story )
    {
        die "Story ID $stories_id was not found.";
    }

    my $stories_url = $story->{ url };
    unless ( $stories_url )
    {
        die "Story URL for story ID $stories_id is empty.";
    }

    my $string_start_date = DateTime->from_epoch( epoch => $start_timestamp, time_zone => 'Etc/GMT' )->date();
    my $string_end_date   = DateTime->from_epoch( epoch => $end_timestamp,   time_zone => 'Etc/GMT' )->date();

    my $link_lookup;
    eval { $link_lookup = MediaWords::Util::Bitly::bitly_link_lookup_hashref_all_variants( $stories_url ); };
    if ( $@ or ( !$link_lookup ) )
    {
        die "Unable to lookup story ID $stories_id with URL $stories_url: $@";
    }

    say STDERR "Link lookup: " . Dumper( $link_lookup );

    # Fetch link information for all Bit.ly links at once
    my $bitly_info = {};
    my $bitly_ids = [ grep { defined $_ } values %{ $link_lookup } ];

    say STDERR "Fetching info for Bit.ly IDs " . join( ', ', @{ $bitly_ids } ) . "...";
    if ( scalar( @{ $bitly_ids } ) )
    {
        eval { $bitly_info = MediaWords::Util::Bitly::bitly_info_hashref( $bitly_ids ); };
        if ( $@ or ( !$bitly_info ) )
        {
            die "Unable to fetch Bit.ly info for Bit.ly IDs " . join( ', ', @{ $bitly_ids } ) . ": $@";
        }
    }

    say STDERR "Link info: " . Dumper( $bitly_info );

    my $link_stats = {};

    # Fetch Bit.ly stats for the link (if any)
    foreach my $link ( keys %{ $link_lookup } )
    {

        unless ( defined $link_lookup->{ $link } )
        {
            next;
        }

        unless ( defined $link_stats->{ 'data' } )
        {
            $link_stats->{ 'data' } = {};
        }

        my $bitly_id = $link_lookup->{ $link };

        say STDERR "Fetching stats for Bit.ly ID $bitly_id...";
        if ( $link_stats->{ 'data' }->{ $bitly_id } )
        {
            die "Bit.ly ID $bitly_id already exists in link stats hashref: " . Dumper( $link_stats );
        }

        $link_stats->{ 'data' }->{ $bitly_id } = {};

        if ( $stats_to_fetch->{ fetch_categories } )
        {
            say STDERR "Fetching categories for Bit.ly ID $bitly_id...";
            $link_stats->{ 'data' }->{ $bitly_id }->{ 'categories' } =
              MediaWords::Util::Bitly::bitly_link_categories( $bitly_id );
        }
        if ( $stats_to_fetch->{ fetch_clicks } )
        {
            say STDERR "Fetching clicks for Bit.ly ID $bitly_id for date range $string_start_date - $string_end_date...";
            $link_stats->{ 'data' }->{ $bitly_id }->{ 'clicks' } = [

                # array because one might want to make multiple requests with various dates
                MediaWords::Util::Bitly::bitly_link_clicks( $bitly_id, $start_timestamp, $end_timestamp )
            ];
        }
        if ( $stats_to_fetch->{ fetch_referrers } )
        {
            say STDERR "Fetching referrers for Bit.ly ID $bitly_id for date range $string_start_date - $string_end_date...";
            $link_stats->{ 'data' }->{ $bitly_id }->{ 'referrers' } = [

                # array because one might want to make multiple requests with various dates
                MediaWords::Util::Bitly::bitly_link_referrers( $bitly_id, $start_timestamp, $end_timestamp )
            ];
        }
        if ( $stats_to_fetch->{ fetch_shares } )
        {
            say STDERR "Fetching shares for Bit.ly ID $bitly_id for date range $string_start_date - $string_end_date...";
            $link_stats->{ 'data' }->{ $bitly_id }->{ 'shares' } = [

                # array because one might want to make multiple requests with various dates
                MediaWords::Util::Bitly::bitly_link_shares( $bitly_id, $start_timestamp, $end_timestamp )
            ];
        }

    }

    # No links?
    if ( scalar( keys %{ $link_stats } ) )
    {

        # Collection timestamp (GMT, not local time)
        $link_stats->{ 'collection_timestamp' } = time();

    }
    else
    {

        # Mark as "not found"
        $link_stats->{ 'error' } = 'NOT_FOUND';
    }

    return $link_stats;
}

sub write_story_stats($$$;$)
{
    my ( $db, $stories_id, $stats, $overwrite ) = @_;

    unless ( MediaWords::Util::Bitly::bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    unless ( $stories_id )
    {
        die "'stories_id' is not set.";
    }
    unless ( ref( $stats ) eq ref( {} ) )
    {
        die "Stats is not a hashref.";
    }

    # Check if something is already stored
    my $record_exists = undef;
    eval { $record_exists = $_gridfs_store->content_exists( $db, $stories_id ); };
    if ( $@ )
    {
        die "GridFS died while testing whether or not a Bit.ly record exists for story $stories_id: $@";
    }

    if ( $record_exists )
    {
        if ( $overwrite )
        {
            say STDERR "Bit.ly record for story $stories_id already exists in GridFS, will overwrite.";
        }
        else
        {
            die "Bit.ly record for story $stories_id already exists in GridFS.";
        }
    }

    # Convert results to a minimized JSON
    my $json_stats;
    eval { $json_stats = MediaWords::Util::JSON::encode_json( $stats ); };
    if ( $@ or ( !$json_stats ) )
    {
        die "Unable to encode hashref to JSON: $@\nHashref: " . Dumper( $stats );
    }

    say STDERR 'JSON length: ' . length( $json_stats );

    # Write to GridFS, index by stories_id
    eval {
        my $param_skip_encode_and_compress  = 0;    # Objects should be compressed
        my $param_use_bzip2_instead_of_gzip = 0;    # Gzip works better in Bit.ly's case

        my $path = $_gridfs_store->store_content(
            $db, $stories_id, \$json_stats,
            $param_skip_encode_and_compress,
            $param_use_bzip2_instead_of_gzip
        );
    };
    if ( $@ )
    {
        die "Unable to store Bit.ly result to GridFS: $@";
    }
}

1;
