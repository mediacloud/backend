package MediaWords::Crawler::Download::DefaultFetcher;

#
# Default fetcher implementation
#
# In addition to the basic HTTP request with the user agent options supplied by
# MediaWords::Util::Web::user_agent(), the default fetcher:
#
# * fixes common url mistakes like doubling http: (http://http://google.com).
# * follows meta refresh redirects in the response content
# * adds domain specific http auth specified in mediawords.yml
# * implements a very limited amount of site specific fixes
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose::Role;
with 'MediaWords::Crawler::FetcherRole';

use MediaWords::DB;
use MediaWords::Util::Config;
use MediaWords::Util::SQL;
use MediaWords::Util::Web;
use MediaWords::Util::URL;

# alarabiya uses an interstitial that requires javascript.  if the download url
# matches alarabiya and returns the 'requires JavaScript' page, manually parse
# out the necessary cookie and add it to the $ua so that the request will work
sub _fix_alarabiya_response
{
    my ( $download, $ua, $response ) = @_;

    return $response unless ( $download->{ url } =~ /alarabiya/ );

    if ( $response->content !~ /This site requires JavaScript and Cookies to be enabled/ )
    {
        return $response;
    }

    if ( $response->content =~ /setCookie\('([^']+)', '([^']+)'/ )
    {
        my $response = $ua->get( $download->{ url }, Cookie => "$1=$2" );

        return $response;
    }
    else
    {
        WARN "Unable to parse cookie from alarabiya: " . $response->content;
        return $response;
    }
}

# cache domain http auth lookup from config
my $_domain_http_auth_lookup;

# read the mediawords.crawler_authenticated_domains list from mediawords.yml and generate a lookup hash
# with the host domain as the key and the user:password credentials as the value.
sub _get_domain_http_auth_lookup
{
    return $_domain_http_auth_lookup if ( defined( $_domain_http_auth_lookup ) );

    my $config = MediaWords::Util::Config::get_config;

    my $domains = $config->{ mediawords }->{ crawler_authenticated_domains };

    map { $_domain_http_auth_lookup->{ lc( $_->{ domain } ) } = $_ } @{ $domains };

    return $_domain_http_auth_lookup;
}

# if there are http auth credentials for the requested site, add them to the request
sub _add_http_auth
{
    my ( $download, $request ) = @_;

    my $auth_lookup ||= _get_domain_http_auth_lookup();

    my $domain = MediaWords::Util::URL::get_url_distinctive_domain( $download->{ url } );

    if ( my $auth = $auth_lookup->{ lc( $domain ) } )
    {
        $request->authorization_basic( $auth->{ user }, $auth->{ password } );
    }
}

sub fetch_download($$$)
{
    my ( $self, $db, $download ) = @_;

    $download->{ download_time } = MediaWords::Util::SQL::sql_now;
    $download->{ state }         = 'fetching';

    $db->update_by_id( "downloads", $download->{ downloads_id }, $download );

    my $ua = MediaWords::Util::Web::user_agent();

    my $url = MediaWords::Util::URL::fix_common_url_mistakes( $download->{ url } );

    my $request = HTTP::Request->new( GET => $url );

    _add_http_auth( $download, $request );

    my $response = $ua->request( $request );

    $response = _fix_alarabiya_response( $download, $ua, $response );

    $response = MediaWords::Util::Web::get_meta_redirect_response( $response, $request->uri->as_string );

    return $response;
}

1;
