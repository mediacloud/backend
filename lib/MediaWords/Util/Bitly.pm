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
use MediaWords::Util::DateTime;
use URI;
use URI::QueryParam;
use JSON;
use Scalar::Util qw/looks_like_number/;
use Scalar::Defer;
use DateTime;
use DateTime::Duration;
use Readonly;

# API endpoint
Readonly my $BITLY_API_ENDPOINT => 'https://api-ssl.bitly.com/';

# PostgreSQL table name for storing raw Bit.ly processing results
Readonly my $BITLY_POSTGRESQL_KVS_TABLE_NAME => 'bitly_processing_results';

# Whether to compress processing results using Bzip2 instead of Gzip
Readonly my $BITLY_USE_BZIP2 => 0;    # Gzip works better in Bit.ly's case

# Error message printed when Bit.ly rate limit is exceeded; used for naive
# exception handling, see error_is_rate_limit_exceeded()
Readonly my $BITLY_ERROR_LIMIT_EXCEEDED => 'Bit.ly rate limit exceeded. Please wait for a bit and try again.';

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

# (Lazy-initialized) PostgreSQL key-value store
#
# We use a static, package-wide variable here because:
# a) PostgreSQL handler should support being used by multiple threads by now, and
# b) each Gearman worker is a separate process so there shouldn't be any resource clashes.
my $_postgresql_store = lazy
{
    # this is (probably) an expensive module to load, so lazy load it
    require MediaWords::KeyValueStore::PostgreSQL;

    unless ( bitly_processing_is_enabled() )
    {
        fatal_error( "Bit.ly processing is not enabled; why are you accessing this variable?" );
    }

    # PostgreSQL storage
    my $postgresql_store = MediaWords::KeyValueStore::PostgreSQL->new( { table => $BITLY_POSTGRESQL_KVS_TABLE_NAME } );
    say STDERR "Will read / write Bit.ly stats to PostgreSQL table: $BITLY_POSTGRESQL_KVS_TABLE_NAME";

    return $postgresql_store;
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

        my $start_date = gmt_datetime_from_timestamp( $start_timestamp );
        my $end_date   = gmt_datetime_from_timestamp( $end_timestamp );

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
            die 'Difference (' . $delta_days . ' days) between start_timestamp (' . $start_timestamp .
              ') and end_timestamp (' . $end_timestamp . ') is bigger than Bit.ly\'s limit (' . $max_bitly_limit . ' days).';
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

    my $uri = URI->new( $BITLY_API_ENDPOINT );
    $uri->path( $path );
    foreach my $params_key ( keys %{ $params } )
    {
        $uri->query_param( $params_key => $params->{ $params_key } );
    }
    $uri->query_param( $params );
    my $url = $uri->as_string;

    my $ua = MediaWords::Util::Web::UserAgentDetermined;
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
        if ( $json->{ status_code } == 403 and $json->{ status_txt } eq 'RATE_LIMIT_EXCEEDED' )
        {
            die $BITLY_ERROR_LIMIT_EXCEEDED;

        }
        elsif ( $json->{ status_code } == 500 and $json->{ status_txt } eq 'INVALID_ARG_UNIT_REFERENCE_TS' )
        {

            my $error_message = '';
            $error_message .= 'Invalid timestamp ("unit_reference_ts" argument) which is ';
            if ( defined $params->{ unit_reference_ts } )
            {
                $error_message .= $params->{ unit_reference_ts };
                $error_message .= ' (' . gmt_date_string_from_timestamp( $params->{ unit_reference_ts } ) . ')';
            }
            else
            {
                $error_message .= 'undef';
            }
            $error_message .= '; request parameters: ' . Dumper( $params );

            die $error_message;
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
        unless ( $link_lookup_item->{ error } )
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
sub bitly_link_lookup_hashref_all_variants($$)
{
    my ( $db, $url ) = @_;

    unless ( bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    my @urls = MediaWords::Util::URL::all_url_variants( $db, $url );
    unless ( scalar @urls )
    {
        die "No URLs returned for URL $url";
    }

    return bitly_link_lookup_hashref( \@urls );
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

{
    # Object to determine what kind of stats to fetch from Bit.ly (used in
    # fetch_stats_for_story())
    package MediaWords::Util::Bitly::StatsToFetch;

    sub new($;$)
    {
        my $class = shift;
        my ( $fetch_clicks ) = @_;

        my $self = {};
        bless $self, $class;

        # Default values
        $self->{ fetch_clicks } = $fetch_clicks // 1;

        return $self;
    }

    1;
}

# Check if story has to be processed with Bit.ly (controversies.process_with_bitly == 't')
# Return 1 if story has to be processed with Bit.ly, 0 otherwise, die() on error, exit() on fatal error
sub story_is_enabled_for_processing($$)
{
    my ( $db, $stories_id ) = @_;

    unless ( bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    my $story = $db->query(
        <<EOF,
        SELECT 1 AS story_is_enabled_for_bitly_processing
        FROM controversy_stories
            INNER JOIN controversies ON controversy_stories.controversies_id = controversies.controversies_id
        WHERE stories_id = ?
          AND controversies.process_with_bitly = 't';
EOF
        $stories_id
    )->hash;
    if ( $story->{ story_is_enabled_for_bitly_processing } )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Check if story is processed with Bit.ly (stats are fetched)
# Return 1 if stats for story are fetched, 0 otherwise, die() on error, exit() on fatal error
sub story_stats_are_fetched($$)
{
    my ( $db, $stories_id ) = @_;

    unless ( bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    my $record_exists = undef;
    eval { $record_exists = $_postgresql_store->content_exists( $db, $stories_id ); };
    if ( $@ )
    {
        die "Storage died while testing whether or not a Bit.ly record exists for story $stories_id: $@";
    }

    if ( $record_exists )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Fetch story URL statistics from Bit.ly API
#
# Params:
# * $db - database object
# * $stories_id - story ID
# * $start_timestamp - starting date (offset) for fetching statistics
# * $end_timestamp - ending date (limit) for fetching statistics
# * $stats_to_fetch (optional) - object of type
#   "MediaWords::Util::Bitly::StatsToFetch" which determines what kind of
#   statistics to fetch for the story
#
# Returns: see fetch_stats_for_url()
#
# die()s on error
sub fetch_stats_for_story($$$$;$)
{
    my ( $db, $stories_id, $start_timestamp, $end_timestamp, $stats_to_fetch ) = @_;

    my $story = $db->find_by_id( 'stories', $stories_id );
    unless ( $story )
    {
        die "Story ID $stories_id was not found.";
    }

    my $stories_url = $story->{ url };

    return fetch_stats_for_url( $db, $stories_url, $start_timestamp, $end_timestamp, $stats_to_fetch );
}

# Fetch story URL statistics from Bit.ly API
#
# Params:
# * $db - database object
# * $stories_url - story URL
# * $start_timestamp - starting date (offset) for fetching statistics
# * $end_timestamp - ending date (limit) for fetching statistics
# * $stats_to_fetch (optional) - object of type
#   "MediaWords::Util::Bitly::StatsToFetch" which determines what kind of
#   statistics to fetch for the story
#
# Returns: hashref with statistics, e.g.:
#    {
#        'collection_timestamp' => 1409135396,
#        'data' => {
#            '1boI7Cn' => {
#                'clicks' => [
#                    {
#                        'link_clicks' => [
#                            {
#                                'clicks' => 0,
#                                'dt' => 1408492800
#                            },
#                            {
#                                'clicks' => 0,
#                                'dt' => 1408406400
#                            },
#                            ...
#                            {
#                                'clicks' => 0,
#                                'dt' => 1406937600
#                            }
#                        ],
#                        'unit' => 'day',
#                        'unit_reference_ts' => 1408492800,
#                        'tz_offset' => 0,
#                        'units' => 19
#                    }
#                ],
#                'referrers' => [
#                    {
#                        'unit' => 'day',
#                        'unit_reference_ts' => 1408492800,
#                        'referrers' => [],
#                        'tz_offset' => 0,
#                        'units' => 19
#                    }
#                ]
#            }
#        }
#    };
#
# die()s on error
sub fetch_stats_for_url($$$$;$)
{
    my ( $db, $stories_url, $start_timestamp, $end_timestamp, $stats_to_fetch ) = @_;

    unless ( $stories_url )
    {
        die "Story URL is empty.";
    }

    unless ( bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    {
        local $Data::Dumper::Indent = 0;

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

    my $string_start_date = gmt_date_string_from_timestamp( $start_timestamp );
    my $string_end_date   = gmt_date_string_from_timestamp( $end_timestamp );

    my $link_lookup;
    eval { $link_lookup = bitly_link_lookup_hashref_all_variants( $db, $stories_url ); };
    if ( $@ or ( !$link_lookup ) )
    {
        die "Unable to lookup story with URL $stories_url: $@";
    }

    say STDERR "Link lookup: " . Dumper( $link_lookup );

    # Fetch link information for all Bit.ly links at once
    my $bitly_info = {};
    my $bitly_ids = [ grep { defined $_ } values %{ $link_lookup } ];

    say STDERR "Fetching info for Bit.ly IDs " . join( ', ', @{ $bitly_ids } ) . "...";
    if ( scalar( @{ $bitly_ids } ) )
    {
        eval { $bitly_info = bitly_info_hashref( $bitly_ids ); };
        if ( $@ or ( !$bitly_info ) )
        {
            die "Unable to fetch Bit.ly info for Bit.ly IDs " . join( ', ', @{ $bitly_ids } ) . ": $@";
        }
    }

    # say STDERR "Link info: " . Dumper( $bitly_info );

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

        if ( $link_stats->{ 'data' }->{ $bitly_id } )
        {
            die "Bit.ly ID $bitly_id already exists in link stats hashref: " . Dumper( $link_stats );
        }

        $link_stats->{ 'data' }->{ $bitly_id } = {};

        # Append link
        $link_stats->{ 'data' }->{ $bitly_id }->{ 'url' } = $link;

        # Append "/v3/link/info" block
        unless ( $bitly_info->{ $bitly_id } )
        {
            die "Bit.ly ID $bitly_id was not found in the 'info' hashref: " . Dumper( $bitly_info );
        }
        $link_stats->{ 'data' }->{ $bitly_id }->{ 'info' } = $bitly_info->{ $bitly_id };

        say STDERR "Fetching stats for Bit.ly ID $bitly_id...";

        if ( $stats_to_fetch->{ fetch_clicks } )
        {
            say STDERR "Fetching clicks for Bit.ly ID $bitly_id for date range $string_start_date - $string_end_date...";
            $link_stats->{ 'data' }->{ $bitly_id }->{ 'clicks' } = [

                # array because one might want to make multiple requests with various dates
                bitly_link_clicks( $bitly_id, $start_timestamp, $end_timestamp )
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

# Write Bit.ly story statistics to key-value store; overwrite if a record
# already exists in the store
#
# Params:
# * $db - database object
# * $stories_id - story ID
# * $stats - hashref with Bit.ly statistics
#
# die()s on error
sub write_story_stats($$$)
{
    my ( $db, $stories_id, $stats ) = @_;

    unless ( bitly_processing_is_enabled() )
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
    if ( story_stats_are_fetched( $db, $stories_id ) )
    {
        warn "Story's $stories_id stats are already fetched from Bit.ly, so I will overwrite it.";
    }

    # Convert results to a minimized JSON
    my $json_stats;
    eval { $json_stats = MediaWords::Util::JSON::encode_json( $stats ); };
    if ( $@ or ( !$json_stats ) )
    {
        die "Unable to encode hashref to JSON: $@\nHashref: " . Dumper( $stats );
    }

    say STDERR 'JSON length: ' . length( $json_stats );

    # Write to key-value store, index by stories_id
    eval {
        my $param_use_bzip2_instead_of_gzip = $BITLY_USE_BZIP2;

        my $path = $_postgresql_store->store_content( $db, $stories_id, \$json_stats, $param_use_bzip2_instead_of_gzip );
    };
    if ( $@ )
    {
        die "Unable to store Bit.ly result to store: $@";
    }
}

# Read Bit.ly story statistics from key-value store
#
# Params:
# * $db - database object
# * $stories_id - story ID
#
# Returns hashref with decoded JSON, undef if story is not processed; die()s on error
sub read_story_stats($$)
{
    my ( $db, $stories_id ) = @_;

    unless ( bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    unless ( $stories_id )
    {
        die "'stories_id' is not set.";
    }

    # Check if something is already stored
    unless ( story_stats_are_fetched( $db, $stories_id ) )
    {
        warn "Story $stories_id is not processed with Bit.ly.";
        return undef;
    }

    # Fetch processing result
    my $json_ref = undef;

    my $param_object_path                   = undef;
    my $param_use_bunzip2_instead_of_gunzip = $BITLY_USE_BZIP2;

    eval {
        $json_ref =
          $_postgresql_store->fetch_content( $db, $stories_id, $param_object_path, $param_use_bunzip2_instead_of_gunzip );
    };
    if ( $@ or ( !defined $json_ref ) )
    {
        die "Storage died while fetching Bit.ly stats for story $stories_id: $@\n";
    }

    my $json = $$json_ref;
    unless ( $json )
    {
        die "Fetched stats are undefined or empty for story $stories_id.\n";
    }

    my $json_hashref;
    eval { $json_hashref = MediaWords::Util::JSON::decode_json( $json ); };
    if ( $@ or ( !ref $json_hashref ) )
    {
        die "Unable to parse Bit.ly stats JSON for story $stories_id: $@\nString JSON: $json";
    }

    return $json_hashref;
}

# Return the number of controversy's stories that don't yet have aggregated Bit.ly statistics
sub num_controversy_stories_without_bitly_statistics($$)
{
    my ( $db, $controversies_id ) = @_;

    my ( $num_controversy_stories_without_bitly_statistics ) = $db->query(
        <<EOF,
        SELECT num_controversy_stories_without_bitly_statistics(?)
EOF
        $controversies_id
    )->flat;
    unless ( defined $num_controversy_stories_without_bitly_statistics )
    {
        die "'num_controversy_stories_without_bitly_statistics' is undefined.";
    }

    return $num_controversy_stories_without_bitly_statistics;
}

# Given the error message ($@ after unsuccessful eval{}), determine whether the
# error is because of the exceeded Bit.ly rate limit
sub error_is_rate_limit_exceeded($)
{
    my $error_message = shift;

    if ( $error_message =~ /$BITLY_ERROR_LIMIT_EXCEEDED/ )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

{
    # Single story statistics
    package MediaWords::Util::Bitly::StoryStats;

    sub new($$;$$)
    {
        my $class = shift;
        my ( $stories_id, $click_count ) = @_;

        my $self = {};
        bless $self, $class;

        $self->{ stories_id } = $stories_id;
        $self->{ click_count } = $click_count // 0;

        return $self;
    }

    1;
}

# Returns MediaWords::Util::Bitly::StoryStats object with story statistics
# die()s on error
sub aggregate_story_stats($$$)
{
    my ( $stories_id, $stories_original_url, $stats ) = @_;

    my $click_count = 0;

    # Aggregate stats
    if ( $stats->{ 'error' } )
    {
        if ( $stats->{ 'error' } eq 'NOT_FOUND' )
        {
            say STDERR "Story $stories_id was not found on Bit.ly, so click count is 0.";
        }
        else
        {
            die "Story $stories_id has encountered unknown error while collecting Bit.ly stats: " . $stats->{ 'error' };
        }
    }
    else
    {
        my $stories_original_url_is_homepage = MediaWords::Util::URL::is_homepage_url( $stories_original_url );

        unless ( $stats->{ 'data' } )
        {
            die "'data' is not set for story's $stories_id stats hashref.";
        }

        foreach my $bitly_id ( keys %{ $stats->{ 'data' } } )
        {
            my $bitly_data = $stats->{ 'data' }->{ $bitly_id };

            # If URL gets redirected to the homepage (e.g.
            # http://m.wired.com/threatlevel/2011/12/sopa-watered-down-amendment/ leads
            # to http://www.wired.com/), don't use those redirects
            my $url = $bitly_data->{ 'url' };
            unless ( $stories_original_url_is_homepage )
            {
                if ( MediaWords::Util::URL::is_homepage_url( $url ) )
                {
                    say STDERR
                      "URL $stories_original_url got redirected to $url which looks like a homepage, so I'm skipping that.";
                    next;
                }
            }

            # Click count (indiscriminate from date range)
            unless ( $bitly_data->{ 'clicks' } )
            {
                say "Bit.ly stats hashref doesn't have 'clicks' key for Bit.ly ID $bitly_id, story $stories_id.";
            }
            foreach my $bitly_clicks ( @{ $bitly_data->{ 'clicks' } } )
            {
                foreach my $link_clicks ( @{ $bitly_clicks->{ 'link_clicks' } } )
                {
                    $click_count += $link_clicks->{ 'clicks' };
                }
            }
        }
    }

    return MediaWords::Util::Bitly::StoryStats->new( $stories_id, $click_count );
}

1;
