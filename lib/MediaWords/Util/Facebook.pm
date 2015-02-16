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

# Facebook Graph API version to use
Readonly my $FACEBOOK_GRAPH_API_VERSION => 'v2.2';

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

    my $ua = MediaWords::Util::Web::UserAgentDetermined();
    $ua->timing( '1,3,15,60,300,600' );
    $ua->timeout( $config->{ facebook }->{ timeout } );

    my $response;
    eval { $response = $ua->get( $api_uri->as_string ); };
    if ( $@ )
    {
        fatal_error( 'LWP::UserAgent::Determined died while fetching response: ' . $@ );
    }

    my $decoded_content = $response->decoded_content;
    my $data;
    eval { $data = MediaWords::Util::JSON::decode_json( $decoded_content ); };

    unless ( $response->is_success )
    {
        if ( $decoded_content )
        {
            if ( $data )
            {
                if ( defined $data->{ error } )
                {
                    my $error_message = $data->{ error }->{ message };
                    my $error_type    = $data->{ error }->{ type };
                    my $error_code    = $data->{ error }->{ code } + 0;

                    # Error response is JSON -- most of Facebook's errors mean
                    # that we can't continue further
                    fatal_error( "Facebook API returned an error while " .
                          "fetching stats for URL $url: ($error_code " . "$error_type) $error_message" );
                }
            }

            # Error response is not in JSON
            fatal_error( "Error fetching stats for URL $url: $decoded_content" );
        }

        # Error response is empty
        fatal_error( "Unknown error fetching stats for URL $url" );
    }

    unless ( defined $data->{ og_object } and defined $data->{ share } and defined $data->{ id } )
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

    my $share_count   = $data->{ share }->{ share_count }   || 0;
    my $comment_count = $data->{ share }->{ comment_count } || 0;

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
                facebook_api_error = \$4
            WHERE stories_id = \$1
            RETURNING *
        )
        INSERT INTO story_statistics (
            stories_id,
            facebook_share_count,
            facebook_comment_count,
            facebook_api_error
        )
            SELECT \$1, \$2, \$3, \$4
            WHERE NOT EXISTS ( SELECT * FROM try_update )
END
        $story->{ stories_id }, $share_count, $comment_count, $error
    );

    return ( $share_count, $comment_count );

}
1;
