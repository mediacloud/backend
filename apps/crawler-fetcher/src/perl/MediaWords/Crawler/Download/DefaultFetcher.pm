package MediaWords::Crawler::Download::DefaultFetcher;

#
# Default fetcher implementation
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose::Role;
with 'MediaWords::Crawler::FetcherRole';

use MediaWords::Util::SQL;
use MediaWords::Util::Web;
use MediaWords::Util::URL;

sub fetch_download($$$)
{
    my ( $self, $db, $download ) = @_;

    $download->{ download_time } = MediaWords::Util::SQL::sql_now;
    $download->{ state }         = 'fetching';

    $db->update_by_id( "downloads", $download->{ downloads_id }, $download );

    my $ua = MediaWords::Util::Web::UserAgent->new();

    my $url = $download->{ url };

    my $response = $ua->get_follow_http_html_redirects( $url );

    return $response;
}

1;
