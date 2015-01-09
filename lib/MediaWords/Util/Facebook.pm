package MediaWords::Util::Facebook;

#
# Facebook API helper
#

use strict;
use warnings;

use URI::Escape;
use Readonly;

use MediaWords::Util::JSON;
use MediaWords::Util::URL;
use MediaWords::Util::Web;

sub _get_single_url_share_count
{
    my ( $ua, $url ) = @_;

    # this is mostly to be able to generate an error for testing
    die( "invalid url: '$url'" ) if ( $url !~ /^http/i );

    my $response = $ua->get( 'https://graph.facebook.com/?id=' . uri_escape_utf8( $url ) );

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

    Readonly my $treat_fragment_as_path => 1;
    my $all_urls = [ MediaWords::Util::URL::all_url_variants( $db, $url, $treat_fragment_as_path ) ];

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

    $db->query( <<END, $story->{ stories_id }, $count, $error );
with try_update as (
  update story_statistics 
        set facebook_share_count = \$2, facebook_share_count_error = \$3
        where stories_id = \$1
        returning *
)
insert into story_statistics ( stories_id, facebook_share_count, facebook_share_count_error )
    select \$1, \$2, \$3
        where not exists ( select * from try_update );
END

    return $count;

}
1;
