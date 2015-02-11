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

# Facebook Graph API version to use
Readonly my $FACEBOOK_GRAPH_API_VERSION => 'v2.2';

sub _get_single_url_share_comment_counts
{
    my ( $ua, $url ) = @_;

    # this is mostly to be able to generate an error for testing
    die( "invalid url: '$url'" ) if ( $url !~ /^http/i );

    my $api_uri = URI->new( "https://graph.facebook.com/$FACEBOOK_GRAPH_API_VERSION/" );
    $api_uri->query_param_append( 'id', $url );

    my $response = $ua->get( $api_uri->as_string );

    unless ( $response->is_success )
    {
        die "Error fetching stats for URL: $url";
    }
    my $decoded_content = $response->decoded_content;

    my $data = MediaWords::Util::JSON::decode_json( $decoded_content );

    if ( defined $data->{ error } )
    {
        my $error_message = $data->{ error }->{ message };
        my $error_type    = $data->{ error }->{ type };
        my $error_code    = $data->{ error }->{ code };

        die "Facebook API returned an error while fetching stats for " .
          "URL $url: ($error_code $error_type) $error_message";
    }

    unless ( defined $data->{ og_object } and defined $data->{ share } and defined $data->{ id } )
    {
        die "Returned data JSON is invalid for URL $url: " . Dumper( $data );
    }

    my $share_count   = $data->{ share }->{ share_count }   || 0;
    my $comment_count = $data->{ share }->{ comment_count } || 0;

    return ( $share_count, $comment_count );
}

# use https://graph.facebook.com/?id= to get number of shares for the given url
# https://graph.facebook.com/?id=http://www.google.com/
sub get_url_share_comment_counts
{
    my ( $db, $url ) = @_;

    my $all_urls = [ MediaWords::Util::URL::all_url_variants( $db, $url ) ];

    my $ua = MediaWords::Util::Web::UserAgentDetermined();
    $ua->timing( '1,3,15,60,300,600' );

    my $url_share_counts   = {};
    my $url_comment_counts = {};
    for my $u ( @{ $all_urls } )
    {
        my ( $share_count, $comment_count ) = _get_single_url_share_comment_counts( $ua, $u );

        say STDERR "* Share count: $share_count, comment count: $comment_count, URL variant: $u";

        $url_share_counts->{ $share_count }     = $u;
        $url_comment_counts->{ $comment_count } = $u;
    }

    my $share_count_sum   = List::Util::sum( keys( %{ $url_share_counts } ) );
    my $comment_count_sum = List::Util::sum( keys( %{ $url_comment_counts } ) );

    return ( $share_count_sum, $comment_count_sum );
}

sub get_and_store_share_comment_counts
{
    my ( $db, $story ) = @_;

    my $config = MediaWords::Util::Config::get_config();
    unless ( $config->{ facebook }->{ enabled } eq 'yes' )
    {
        fatal_error( 'Facebook API processing is not enabled.' );
    }

    my ( $share_count, $comment_count );
    eval { ( $share_count, $comment_count ) = get_url_share_comment_counts( $db, $story->{ url } ); };
    my $error = $@ ? $@ : undef;

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
