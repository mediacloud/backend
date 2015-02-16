package MediaWords::Util::Facebook;

#
# Facebook API helper
#

use strict;
use warnings;

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
Readonly my $FACEBOOK_GRAPH_API_VERSION => 'v2.2';

# Number of retries to do on temporary Facebook Graph API errors (such as rate
# limiting issues or API downtime)
Readonly my $FACEBOOK_GRAPH_API_RETRY_COUNT => 6;

# Time to wait (in seconds) between retries on temporary Facebook Graph API
# errors
Readonly my $FACEBOOK_GRAPH_API_RETRY_WAIT => 10 * 60;

# Facebook Graph API's error codes of temporary errors on which we should retry
# after waiting for a while
#
# (https://developers.facebook.com/docs/graph-api/using-graph-api/v2.2#errors)
Readonly my @FACEBOOK_GRAPH_API_TEMPORARY_ERROR_CODES => (

    # API Unknown -- Possibly a temporary issue due to downtime - retry the
    # operation after waiting, if it occurs again, check you are requesting an
    # existing API.
    1,

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

# use https://graph.facebook.com/?id= to get number of shares for the given url
# https://graph.facebook.com/?id=http://www.google.com/
sub get_url_share_comment_counts
{
    my ( $db, $url ) = @_;

    unless ( MediaWords::Util::URL::is_http_url( $url ) )
    {
        die "Invalid URL: $url";
    }

    # Canonicalize URL
    my $uri = URI->new( $url )->canonical;
    unless ( $uri )
    {
        die "Unable to create URI object for URL: $url";
    }
    $url = $uri->as_string;

    my $api_uri = URI->new( "https://graph.facebook.com/$FACEBOOK_GRAPH_API_VERSION/" );
    $api_uri->query_param_append( 'id', $url );

    my $config       = MediaWords::Util::Config::get_config();
    my $access_token = $config->{ facebook }->{ app_id } . '|' . $config->{ facebook }->{ app_secret };
    $api_uri->query_param_append( 'access_token', $access_token );

    my ( $decoded_content, $data );
    for ( my $retry = 1 ; $retry <= $FACEBOOK_GRAPH_API_RETRY_COUNT ; ++$retry )
    {
        if ( $retry > 1 )
        {
            say STDERR 'Retrying #' . $retry . '...';
        }

        my $ua = MediaWords::Util::Web::UserAgentDetermined();
        $ua->timeout( $config->{ facebook }->{ timeout } );

        # UserAgentDetermined will retry on server-side errors; client-side errors
        # will be handled by this module
        $ua->timing( '1,3,15,60,300,600' );

        my $response;
        eval { $response = $ua->get( $api_uri->as_string ); };
        if ( $@ )
        {
            fatal_error( 'LWP::UserAgent::Determined died while fetching response: ' . $@ );
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
                fatal_error( "Unknown error fetching stats for URL $url" );
            }

            unless ( $data )
            {
                # Error response is not in JSON
                fatal_error( "Error fetching stats for URL $url: $decoded_content" );
            }

            unless ( defined $data->{ error } )
            {
                # 'error' key is not present in returned JSON
                fatal_error( "No 'error' key in returned error for URL $url: " . Dumper( $data ) );
            }

            my $error_message = $data->{ error }->{ message };
            my $error_type    = $data->{ error }->{ type };
            my $error_code    = $data->{ error }->{ code } + 0;

            if ( any { $_ == $error_code } @FACEBOOK_GRAPH_API_TEMPORARY_ERROR_CODES )
            {
                # Error is temporary - sleep() and then retry
                say STDERR "Facebook API returned a temporary error " .
                  "while fetching stats for URL $url: ($error_code $error_type) $error_message";
                say STDERR "Will retry after $FACEBOOK_GRAPH_API_RETRY_WAIT seconds";
                sleep( $FACEBOOK_GRAPH_API_RETRY_WAIT );

                # Continue the retry loop
                next;
            }
            else
            {
                # Error response is JSON -- most of Facebook's errors mean
                # that we can't continue further
                fatal_error( "Facebook API returned an error while " .
                      "fetching stats for URL $url: ($error_code $error_type) $error_message" );
            }
        }
    }

    unless ( $decoded_content )
    {
        fatal_error( "Response was successful, but we didn't get any data (probably ran out of retries)" );
    }
    unless ( $data )
    {
        fatal_error( "Response was successful, but we weren't able to decode JSON" );
    }

    unless ( defined $data->{ id } )
    {
        fatal_error( "Returned data JSON is invalid for URL $url: " . Dumper( $data ) );
    }

    # Verify that we got stats for the right URL
    my $returned_url = $data->{ id };
    my $returned_uri = URI->new( $returned_url )->canonical;
    unless ( $returned_uri->eq( $uri ) )
    {
        die "Returned URL ($returned_url) is not the same as requested URL ($url)";
    }

    my $share_count   = $data->{ share }->{ share_count }   // 0;
    my $comment_count = $data->{ share }->{ comment_count } // 0;

    say STDERR "* Share count: $share_count, comment count: $comment_count";

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

    my ( $share_count, $comment_count );
    eval { ( $share_count, $comment_count ) = get_url_share_comment_counts( $db, $story->{ url } ); };
    my $error = $@ ? $@ : undef;

    if ( $error )
    {
        say STDERR "Error while fetching Facebook share / comment counts for story $story->{ stories_id }: $error";
    }

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
