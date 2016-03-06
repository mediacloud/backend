package MediaWords::Crawler::Fetcher;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

=head1 NAME

Mediawords::Crawler::Fetcher - controls and coordinates the work of the crawler provider, fetchers, and handlers

=head1 SYNOPSIS

    # this is a simplified version of the code used crawler to interact with the fetcher

    my $crawler = MediaWords::Crawler::Engine->new();

    my $fetcher = MediaWords::Crawler::Fetcher->new( $crawler );

    # get pending $download from somewhere

    my $response = $fetcher->fetch_download( $download );

=head1 DESCRIPTION

The fetcher is the simplest part of the crawler.  It merely uses LWP to download a url and passes the resulting
HTTP::Response to the Handler.  The fetcher has logic to follow meta refresh redirects and to allow http authentication
according to settings in mediawords.yml.  The fetcher does not retry failed urls (failed downloads may be requeued by
the handler).  The fetcher passes the download response to the handler by calling
MediaWords::Crawler::Handle::handle_response().

=cut

use strict;

use LWP::UserAgent;

use MediaWords::DB;
use DBIx::Simple::MediaWords;
use MediaWords::Util::Config;
use MediaWords::Util::SQL;
use MediaWords::Util::Web;
use MediaWords::Util::URL;

=head1 METHODS

=head2 new( $engine )

Create a new fetcher object.  Must include the parent MediaWords::Crawler::Engine object.

=cut

sub new
{
    my ( $class, $engine ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->engine( $engine );

    return $self;
}

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
        warn( "Unable to parse cookie from alarabiya: " . $response->content );
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

    my $domain = MediaWords::Util::URL::get_url_domain( $download->{ url } );

    if ( my $auth = $auth_lookup->{ lc( $domain ) } )
    {
        $request->authorization_basic( $auth->{ user }, $auth->{ password } );
    }
}

=head2 do_fetch( $download, $db )

With relying on the object state, request the $download and return the HTTP::Response.  This method may be called
as a stand alone function.

In addition to the basic HTTP request with the UserAgent options supplied by MediaWords::Util::Web::UserAgent, this
method:

=over

=item *

fixes common url mistakes like doubling http: (http://http://google.com).

=item *

follows meta refresh redirects in the response content

=item *

adds domain specific http auth specified in mediawords.yml

=item *

implements a very limited amount of site specific fixes

=back

=cut

sub do_fetch
{
    my ( $download, $dbs ) = @_;

    $download->{ download_time } = MediaWords::Util::SQL::sql_now;
    $download->{ state }         = 'fetching';

    $dbs->update_by_id( "downloads", $download->{ downloads_id }, $download );

    my $ua = MediaWords::Util::Web::UserAgent;

    my $url = MediaWords::Util::URL::fix_common_url_mistakes( $download->{ url } );

    my $request = HTTP::Request->new( GET => $url );

    _add_http_auth( $download, $request );

    my $response = $ua->request( $request );

    $response = _fix_alarabiya_response( $download, $ua, $response );

    $response = MediaWords::Util::Web::get_meta_refresh_response( $response, $request );

    return $response;
}

=head2 fetch_download( $download )

Call do_fetch on the given $download

=cut

sub fetch_download
{
    my ( $self, $download ) = @_;

    my $dbs = $self->engine->dbs;

    return do_fetch( $download, $dbs );
}

=head2 engine

getset engine - parent crawler engine object

=cut

sub engine
{
    if ( $_[ 1 ] )
    {
        $_[ 0 ]->{ engine } = $_[ 1 ];
    }

    return $_[ 0 ]->{ engine };
}

1;
