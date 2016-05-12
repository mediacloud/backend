package MediaWords::Util::Facebook;

#
# Facebook API helper
#

use strict;
use warnings;

use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use MediaWords::Util::JSON;
use MediaWords::Util::Process;
use MediaWords::Util::URL;
use MediaWords::Util::Web;

use Readonly;
use URI::QueryParam;
use Data::Dumper;
use List::MoreUtils qw/any/;

# Facebook Graph API version to use
Readonly my $FACEBOOK_GRAPH_API_VERSION => 'v2.5';

# Number of retries to do on temporary Facebook Graph API errors (such as rate limiting issues or API downtime)
Readonly my $FACEBOOK_GRAPH_API_RETRY_COUNT => 22;

# Time to wait (in seconds) between retries on temporary Facebook Graph API errors
Readonly my $FACEBOOK_GRAPH_API_RETRY_WAIT => 10 * 60;

# Facebook Graph API's error codes of temporary errors on which we should retry
# after waiting for a while
#
# (https://developers.facebook.com/docs/graph-api/using-graph-api/v2.2#errors)
Readonly my @FACEBOOK_GRAPH_API_TEMPORARY_ERROR_CODES => (

    # API Service -- Temporary issue due to downtime - retry the operation
    # after waiting.
    2,

    # API Too Many Calls -- Temporary issue due to throttling - retry the
    # operation after waiting and examine your API request volume.
    4,

    # API User Too Many Calls -- emporary issue due to throttling - retry the
    # operation after waiting and examine your API request volume.
    17,

    # Application limit reached -- Temporary issue due to downtime or
    # throttling - retry the operation after waiting and examine your API
    # request volume.
    341

);

# Seconds to wait for before retrying on temporary errors
Readonly my @FACEBOOK_RETRY_INTERVALS => ( 1, 5, 30 );

# URL patterns for which we're sure we won't get correct results (so we won't even try)
Readonly my @URL_PATTERNS_WHICH_WONT_WORK => (

    # Google Search
    qr#^https?://.*?\.google\..{2,7}/(search|webhp).+?#i,

    # Google Trends
    qr#^https?://.*?\.google\..{2,7}/trends/explore.*?#i,
);

Readonly my $MAX_CONSECUTIVE_ERRORS => 3;

# error code can indicate with that facebook just doesn't like the given url or that our app_secret has
# expired.  keep count of how many times we hit error 1 in a row, and LOGDIE if we hit it more than
# $MAX_CONSECUTIVE_ERROR_1 times.
my $_num_consecutive_errors = 0;

# Make Facebook API request
# Returns resulting JSON on success, LOGDIE()s on error
sub api_request($$)
{
    my ( $node, $params ) = @_;

    unless ( defined $node )
    {
        LOGDIE "Node is undefined (node might be an empty string).";
    }

    unless ( ref( $params ) eq ref( [] ) )
    {
        LOGDIE "Params is not an arrayref.";
    }

    my $api_uri = URI->new( "https://graph.facebook.com/$FACEBOOK_GRAPH_API_VERSION/$node" );
    foreach my $param ( @{ $params } )
    {

        unless ( ref( $param ) eq ref( {} ) )
        {
            LOGDIE "Param should be an hashref.";
        }

        my ( $key, $value ) = ( $param->{ key }, $param->{ value } );
        unless ( defined $key and defined $value )
        {
            LOGDIE "Both 'key' and 'value' must be defined.";
        }

        $api_uri->query_param_append( $key, $value );
    }

    my $config       = MediaWords::Util::Config::get_config();
    my $access_token = $config->{ facebook }->{ app_id } . '|' . $config->{ facebook }->{ app_secret };
    $api_uri->query_param_append( 'access_token', $access_token );

    my ( $decoded_content, $data );
    for ( my $retry = 1 ; $retry <= $FACEBOOK_GRAPH_API_RETRY_COUNT ; ++$retry )
    {
        DEBUG( sub { 'Retrying #' . $retry . '...' } ) if ( $retry > 1 );

        my $ua = MediaWords::Util::Web::UserAgentDetermined();
        $ua->timeout( $config->{ facebook }->{ timeout } );

        # UserAgentDetermined will retry on server-side errors; client-side errors
        # will be handled by this module
        $ua->timing( join( ',', @FACEBOOK_RETRY_INTERVALS ) );

        my $response;
        eval { $response = $ua->get( $api_uri->as_string ); };
        if ( $@ )
        {
            LOGDIE 'LWP::UserAgent::Determined LOGDIEd while fetching response: ' . $@;
        }

        $decoded_content = $response->decoded_content;

        eval { $data = MediaWords::Util::JSON::decode_json( $decoded_content ); };

        if ( $response->is_success )
        {
            # Response was successful - break from the retry loop
            last;

        }
        else
        {
            unless ( $decoded_content )
            {
                # Error response is empty
                LOGDIE 'Decoded content is empty';
            }

            unless ( $data )
            {
                # Error response is not in JSON
                LOGDIE "Unable to decode JSON from response; JSON content: $decoded_content";
            }

            unless ( defined $data->{ error } )
            {
                # 'error' key is not present in returned JSON
                LOGDIE 'No "error" key in returned error: ' . Dumper( $data );
            }

            my $error_message = $data->{ error }->{ message };
            my $error_type    = $data->{ error }->{ type };
            my $error_code    = $data->{ error }->{ code } + 0;

            DEBUG( sub { "api error: ($error_code $error_type) $error_message" } );

            # for some reason, facebook consistently returns errors for some urls, so just return a 0 count for a
            # given url until we have run into $MAX_CONSECUTIVE_ERRORS in a row
            if ( ++$_num_consecutive_errors > $MAX_CONSECUTIVE_ERRORS )
            {
                LOGDIE( "more than $MAX_CONSECUTIVE_ERRORS consecutive errors: ($error_type $error_message)" );
            }

            DEBUG( sub { "return 0 count" } );

            return { zero => 1 };
        }
    }

    $_num_consecutive_errors = 0;

    unless ( $decoded_content )
    {
        LOGDIE "Response was successful, but we didn't get any data (probably ran out of retries)";
    }
    unless ( $data )
    {
        LOGDIE "Response was successful, but we weren't able to decode JSON";
    }

    return $data;
}

# use https://graph.facebook.com/?id= to get number of shares for the given url
# https://graph.facebook.com/?id=http://www.google.com/
sub get_url_share_comment_counts
{
    my ( $db, $url ) = @_;

    $url = MediaWords::Util::URL::fix_common_url_mistakes( $url );

    unless ( MediaWords::Util::URL::is_http_url( $url ) )
    {
        LOGDIE "Invalid URL: $url";
    }

    foreach my $url_pattern_which_wont_work ( @URL_PATTERNS_WHICH_WONT_WORK )
    {
        if ( $url =~ $url_pattern_which_wont_work )
        {
            LOGDIE "URL $url matches one of the patterns for URLs that won't work against Facebook API.";
        }
    }

    # Canonicalize URL
    my $uri = URI->new( $url )->canonical;
    unless ( $uri )
    {
        LOGDIE "Unable to create URI object for URL: $url";
    }
    $url = $uri->as_string;

    # Make API request (https://developers.facebook.com/docs/graph-api/reference/v2.3/url)
    my $data;
    eval { $data = api_request( '', [ { key => 'id', value => $url } ] ); };
    if ( $@ )
    {
        my $error_message = $@;

        if ( $error_message =~ /GraphMethodException/i and $error_message =~ /Unsupported get request/i )
        {
            # Non-fatal error
            LOGDIE "Unable to fetch stats for URL that we don't have access to; URL: $url; error message: $error_message";
        }

        fatal_error( "Error while fetching Facebook stats for URL $url: $error_message" );
    }

    return ( 0, 0 ) if ( $data->{ zero } );

    unless ( defined $data->{ id } )
    {
        fatal_error( "Returned data JSON is invalid for URL $url: " . Dumper( $data ) );
    }

    # Verify that we got stats for the right URL
    my $returned_url = $data->{ id };
    my $returned_uri = URI->new( $returned_url )->canonical;
    unless ( $returned_uri->eq( $uri ) )
    {
        LOGDIE "Returned URL ($returned_url) is not the same as requested URL ($url)";
    }

    my $share_count   = $data->{ share }->{ share_count }   // 0;
    my $comment_count = $data->{ share }->{ comment_count } // 0;

    DEBUG( sub { "* Share count: $share_count, comment count: $comment_count" } );

    return ( $share_count, $comment_count );
}

sub get_and_store_share_comment_counts
{
    my ( $db, $story ) = @_;

    my $config = MediaWords::Util::Config::get_config();
    unless ( $config->{ facebook }->{ enabled } eq 'yes' )
    {
        fatal_error( 'Facebook API processing is not enabled.' );
    }
    unless ( $config->{ facebook }->{ app_id } and $config->{ facebook }->{ app_secret } )
    {
        fatal_error( 'Facebook API processing is enabled, but authentication credentials are not set.' );
    }

    my $story_url = $story->{ url };

    my ( $share_count, $comment_count );
    eval {
        # LOGDIE() on URLs for which stats will be incorrect
        foreach my $url_pattern_which_wont_work ( @URL_PATTERNS_WHICH_WONT_WORK )
        {
            if ( $story_url =~ $url_pattern_which_wont_work )
            {
                LOGDIE "URL $story_url matches one of the patterns for URLs that won't work against Facebook API.";
            }
        }

        ( $share_count, $comment_count ) = get_url_share_comment_counts( $db, $story_url );
    };
    my $error = $@ ? $@ : undef;

    ERROR( sub { "Error while fetching Facebook counts for story $story->{ stories_id }: $error" } ) if ( $error );

    $share_count   ||= 0;
    $comment_count ||= 0;

    $db->query(
        <<END,
        WITH try_update AS (
            UPDATE story_statistics
            SET facebook_share_count = \$2,
                facebook_comment_count = \$3,
                facebook_api_collect_date = NOW(),
                facebook_api_error = \$4
            WHERE stories_id = \$1
            RETURNING *
        )
        INSERT INTO story_statistics (
            stories_id,
            facebook_share_count,
            facebook_comment_count,
            facebook_api_collect_date,
            facebook_api_error
        )
            SELECT \$1, \$2, \$3, NOW(), \$4
            WHERE NOT EXISTS ( SELECT * FROM try_update )
END
        $story->{ stories_id }, $share_count, $comment_count, $error
    );

    return ( $share_count, $comment_count );

}
1;
