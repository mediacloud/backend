package MediaWords::Util::Facebook;

#
# Facebook API helper
#

use strict;
use warnings;

use MediaWords::Util::JSON;
use MediaWords::Util::URL;
use MediaWords::Util::Web;

sub _get_single_url_share_count
{
    my ( $ua, $url ) = @_;

    # this is mostly to be able to generate an error for testing
    die( "invalid url: '$url'" ) if ( $url !~ /^http/i );

    my $api_uri = URI->new( 'https://graph.facebook.com/' );
    $api_uri->query_form( 'id' => $url );

    my $response = $ua->get( $api_uri->as_string );

    if ( !$response->is_success )
    {
        die( "error fetching for url '$url'" );
    }
    my $decoded_content = $response->decoded_content;

    my $data = MediaWords::Util::JSON::decode_json( $decoded_content );

    my $shares = $data->{ shares } || 0;

    return $shares || 0;
}

# use https://graph.facebook.com/?id= to get number of shares for the given url
# https://graph.facebook.com/?id=http://www.google.com/
sub get_url_share_count
{
    my ( $db, $url ) = @_;

    my $all_urls = [ MediaWords::Util::URL::all_url_variants( $db, $url ) ];

    my $ua = MediaWords::Util::Web::UserAgentDetermined();
    $ua->timing( '1,3,15,60,300,600' );

    my $url_counts = {};
    for my $u ( @{ $all_urls } )
    {
        my $count = _get_single_url_share_count( $ua, $u );
        $url_counts->{ $count } = $u;
    }

    return List::Util::sum( keys( %{ $url_counts } ) );
}

sub get_and_store_share_count
{
    my ( $db, $story ) = @_;

    my $count;
    eval { $count = get_url_share_count( $db, $story->{ url } ); };
    my $error = $@ ? $@ : undef;
    $count ||= 0;

    $db->query(
        <<END,
        WITH try_update AS (
            UPDATE story_statistics 
            SET facebook_share_count = \$2,
                facebook_api_error = \$3
            WHERE stories_id = \$1
            RETURNING *
        )
        INSERT INTO story_statistics (
            stories_id,
            facebook_share_count,
            facebook_api_error
        )
            SELECT \$1, \$2, \$3
            WHERE NOT EXISTS ( SELECT * FROM try_update )
END
        $story->{ stories_id }, $count, $error
    );

    return $count;

}
1;
