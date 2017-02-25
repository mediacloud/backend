package MediaWords::Util::Web;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

import_python_module( __PACKAGE__, 'mediawords.util.web' );

use MediaWords::Util::Config;

=head1 NAME MediaWords::Util::Web - web related functions

=head1 DESCRIPTION

Various functions to make downloading web pages easier and faster, including parallel and cached fetching.

=cut

use Fcntl;
use File::Temp;
use FileHandle;
use FindBin;
use HTML::TreeBuilder::LibXML;
use LWP::UserAgent;
use LWP::UserAgent::Determined;
use HTTP::Status qw(:constants);
use Storable;
use Readonly;

use MediaWords::Util::Config;
use MediaWords::Util::Paths;
use MediaWords::Util::SQL;
use MediaWords::Util::URL;

Readonly my $MAX_DOWNLOAD_SIZE => 10 * 1024 * 1024;    # Superglue (TV) feeds could grow big
Readonly my $TIMEOUT           => 20;
Readonly my $MAX_REDIRECT      => 15;

# number of links to prefetch at a time for the cached downloads
Readonly my $LINK_CACHE_SIZE => 200;

# for how many times and at what intervals should LWP::UserAgent::Determined
# retry requests
Readonly my $DETERMINED_RETRIES => '1,2,4,8';

# on which HTTP codes should requests be retried
Readonly my @DETERMINED_HTTP_CODES => (

    HTTP_REQUEST_TIMEOUT,
    HTTP_INTERNAL_SERVER_ERROR,
    HTTP_BAD_GATEWAY,
    HTTP_SERVICE_UNAVAILABLE,
    HTTP_GATEWAY_TIMEOUT,
    HTTP_TOO_MANY_REQUESTS

);

# list of downloads to precache downloads for
my $_link_downloads_list;

# precached link downloads
my $_link_downloads_cache;

=head1 FUNCTIONS

=cut

# handler callback assigned to perpare_request as part of the standard _set_lwp_useragent_properties.
# this handler logs all http requests to a file and also invalidates any requests that match the regex in
# mediawords.yml->mediawords->blacklist_url_pattern.
sub _lwp_request_callback($)
{
    my ( $request, $ua, $h ) = @_;

    my $config = MediaWords::Util::Config::get_config;

    my $blacklist_url_pattern = $config->{ mediawords }->{ blacklist_url_pattern };

    my $url = $request->uri->as_string;

    TRACE( "url: $url" );

    my $blacklisted;
    if ( $blacklist_url_pattern && ( $url =~ $blacklist_url_pattern ) )
    {
        $request->uri( "http://blacklistedsite.localhost/$url" );
        $blacklisted = 1;
    }

    my $logfile = "$config->{ mediawords }->{ data_dir }/logs/http_request.log";

    my $fh = FileHandle->new;

    my $is_new_file = !( -f $logfile );

    if ( !$fh->open( ">>$logfile" ) )
    {
        ERROR( "unable to open log file '$logfile': $!" );
        return;
    }

    flock( $fh, Fcntl::LOCK_EX );

    $fh->print( MediaWords::Util::SQL::sql_now . " $url\n" );
    $fh->print( "invalidating blacklist url.  stack: " . Carp::longmess . "\n" ) if ( $blacklisted );

    chmod( 0777, $logfile ) if ( $is_new_file );

    $fh->close;
}

# set default Media Cloud properties for LWP::UserAgent objects
sub _set_lwp_useragent_properties($)
{
    my $ua = shift;

    my $config = MediaWords::Util::Config::get_config;

    $ua->from( $config->{ mediawords }->{ owner } );
    $ua->agent( $config->{ mediawords }->{ user_agent } );

    $ua->timeout( $TIMEOUT );
    $ua->max_size( $MAX_DOWNLOAD_SIZE );
    $ua->max_redirect( $MAX_REDIRECT );
    $ua->env_proxy;
    $ua->cookie_jar( {} );    # temporary cookie jar for an object
    $ua->default_header( 'Accept-Charset' => 'utf-8' );

    $ua->add_handler( request_prepare => \&_lwp_request_callback );

    return $ua;
}

=head2 user_agent()

Return a LWP::UserAgent with media cloud default settings for agent, timeout, max size, etc.

=cut

sub user_agent
{
    my $ua = LWP::UserAgent->new();
    return _set_lwp_useragent_properties( $ua );
}

=head2 user_agent_determined( )

Return a LWP::UserAgent::Determined object with media cloud default settings for agent, timeout, max size, etc.

Uses custom callback to only retry after one of the following responses, which indicate transient problem:
HTTP_REQUEST_TIMEOUT,
HTTP_INTERNAL_SERVER_ERROR,
HTTP_BAD_GATEWAY,
HTTP_SERVICE_UNAVAILABLE,
HTTP_GATEWAY_TIMEOUT

=cut

sub user_agent_determined
{
    my $ua = LWP::UserAgent::Determined->new();

    $ua->timing( $DETERMINED_RETRIES . '' );

    my %http_codes_hr = map { $_ => 1 } @DETERMINED_HTTP_CODES;
    $ua->codes_to_determinate( \%http_codes_hr );

    $ua->before_determined_callback(
        sub {
            my ( $ua, $timing, $duration, $codes_to_determinate, $lwp_args ) = @_;
            my $request = $lwp_args->[ 0 ];
            my $url     = $request->uri;

            TRACE "Trying $url ...";
        }
    );
    $ua->after_determined_callback(
        sub {
            my ( $ua, $timing, $duration, $codes_to_determinate, $lwp_args, $response ) = @_;
            my $request = $lwp_args->[ 0 ];
            my $url     = $request->uri;

            unless ( $response->is_success )
            {
                my $will_retry = 0;
                if ( $codes_to_determinate->{ $response->code } )
                {
                    $will_retry = 1;
                }

                my $message = "Request to $url failed (" . $response->status_line . "), ";
                if ( response_error_is_client_side( $response ) )
                {
                    $message .= 'error is on the client side, ';
                }

                DEBUG( "$message " . ( ( $will_retry && $duration ) ? "retry in ${ duration }s" : "give up" ) );
                TRACE( "full response: " . $response->as_string );
            }
        }
    );

    return _set_lwp_useragent_properties( $ua );
}

# return the first in a list of nodes matching the xpath pattern
sub _find_first_node
{
    my ( $html_tree, $xpath ) = @_;

    my @nodes = $html_tree->findnodes( $xpath );

    my $node = shift @nodes;

    return $node;
}

# given the content of a linkis.com web page, find the original url in the content, which may be in one of
# serveral places in the DOM
sub _get_url_from_linkis_content($$)
{
    my ( $content, $url ) = @_;

    my $html_tree = HTML::TreeBuilder::LibXML->new;
    $html_tree->ignore_unknown( 0 );
    $html_tree->parse_content( $content );

    my $found_url = 0;

    # list of dom search patterns to find nodes with a url and the attributes to use from those nodes as the url
    # for instance the first item matches '<meta property="og:url" content="http://foo.bar">'
    my $dom_maps = [
        [ '//meta[@property="og:url"]',        'content' ],
        [ '//a[@class="js-youtube-ln-event"]', 'href' ],
        [ '//iframe[@id="source_site"]',       'src' ],
    ];

    for my $dom_map ( @{ $dom_maps } )
    {
        my ( $dom_pattern, $url_attribute ) = @{ $dom_map };
        if ( my $node = _find_first_node( $html_tree, $dom_pattern ) )
        {
            my $url = $node->attr( $url_attribute );
            if ( $url !~ m|^https?://linkis.com| )
            {
                return $url;
            }
        }
    }

    # as a last resort, look for the longUrl key in a javascript array
    if ( $content =~ m|"longUrl":\s*"([^"]+)"| )
    {
        my $url = $1;

        # kludge to de-escape \'d characters in javascript -- 99% of urls are captured by the dom stuff above,
        # we shouldn't get to this point often
        $url =~ s/\\//g;

        if ( $url !~ m|^https?://linkis.com| )
        {
            return $url;
        }
    }

    WARN( "no url found for linkis url: $url" );
    return $url;
}

=head2 get_original_url_from_archive_url( $response, $url )

Given a url and optional response from one of the following url archiving sites, return the original url

=cut

sub get_original_url_from_archive_url($$)
{
    my ( $response, $archive_site_url ) = @_;

    if ( $archive_site_url =~ m|^https?://web\.archive\.org/web/(\d+?/)?(https?://.+?)$|i )
    {
        return $2;
    }

    # everything else requires a response, so just return undef if there was not a successful response
    return undef unless ( $response->is_success );

    my $original_url = undef;

    if ( $archive_site_url =~ m|^https?://archive\.is/(.+?)$|i )
    {
        my $canonical_link = MediaWords::Util::URL::link_canonical_url_from_html( $response->decoded_content );
        if ( $canonical_link =~ m|^https?://archive\.is/\d+?/(https?://.+?)$|i )
        {
            $original_url = $1;
        }
        else
        {
            ERROR "Unable to parse original URL from archive.is response '$archive_site_url': $canonical_link";
        }
    }
    elsif ( $archive_site_url =~ m|^https?://[^/]*linkis.com/| )
    {
        $original_url = _get_url_from_linkis_content( $response->decoded_content, $archive_site_url );
        ERROR( "Unable to find url in linkis content for '$archive_site_url'" ) unless ( $original_url );
    }

    return $original_url;
}

=head2 ParallelGet( $urls )

Get urls in parallel by using an external, forking script.  Returns a list of HTTP::Response objects resulting
from the fetches.

=cut

sub ParallelGet
{
    my ( $urls ) = @_;

    return [] unless ( $urls && @{ $urls } );

    my $web_store_input;
    my $results;
    for my $url ( @{ $urls } )
    {
        my $result = { url => $url, file => File::Temp::mktemp( '/tmp/MediaWordsUtilWebXXXXXXXX' ) };

        $web_store_input .= "$result->{ file }:$result->{ url }\n";

        push( @{ $results }, $result );
    }

    my $mc_root_path = MediaWords::Util::Paths::mc_root_path();
    my $cmd          = "'$mc_root_path'/script/mediawords_web_store.pl";

    if ( !open( CMD, '|-', $cmd ) )
    {
        WARN "Unable to start $cmd: $!";
        return;
    }

    binmode( CMD, 'utf8' );

    print CMD $web_store_input;
    close( CMD );

    my $responses;
    for my $result ( @{ $results } )
    {
        my $response;
        if ( -f $result->{ file } )
        {
            $response = Storable::retrieve( $result->{ file } );
            push( @{ $responses }, $response );
            unlink( $result->{ file } );
        }
        else
        {
            $response = HTTP::Response->new( '500', "web store timeout for $result->{ url }" );
            $response->request( HTTP::Request->new( GET => $result->{ url } ) );

            push( @{ $responses }, $response );
        }
    }

    return $responses;
}

=head2 get_original_request( $class, $request )

Walk back from the given response to get the original request that generated the response.

=cut

sub get_original_request
{
    my ( $class, $response ) = @_;

    my $original_response = $response;
    while ( $original_response->previous )
    {
        $original_response = $original_response->previous;
    }

    return $original_response->request;
}

=head2 lookup_by_response_url( $list, $response )

Given a list of hashes, each of which includes a 'url' key, and an HTTP::Response, return the hash in $list for
which the canonical version of the url is the same as the canonical version of the originally requested
url for the response.  Return undef if no match is found.

This function is helpful for associating a given respone returned by ParallelGet with the object that originally
generated the url (for instance, the medium input record that generate the url fetch for the medium title)

=cut

sub lookup_by_response_url($$)
{
    my ( $list, $response ) = @_;

    my $original_request = MediaWords::Util::Web->get_original_request( $response );
    my $url              = URI->new( $original_request->uri->as_string );

    map { return ( $_ ) if ( URI->new( $_->{ url } ) eq $url ) } @{ $list };

    return undef;
}

=head2 cache_link_downloads( $links )

Cache link downloads $LINK_CACHE_SIZE at a time so that we can do them in parallel. This call doesn't actually do any
caching -- it just sets the list of links so that they can be done $LINK_CACHE_SIZE at a time by
get_cached_link_download().

Each link shuold be a hash with either or both 'url' and 'redirect_url' entries.  If both redirect_url and url
are specified in a given link, redirect_url is fetched.

Has a side effect of adding a _link_num and _fetch_url items to each member of $links.


=cut

sub cache_link_downloads
{
    my ( $links ) = @_;

    $_link_downloads_cache = {};
    $_link_downloads_list  = $links;

    my $i = 0;
    for my $link ( @{ $links } )
    {
        $link->{ _link_num } = $i++;
        $link->{ _fetch_url } = $link->{ redirect_url } || $link->{ url };
    }
}

=head2 get_cached_link_download( $link )

Used with cache_link_downloads to download a long list of urls in parallel batches of $LINK_CACHE_SIZE.

Before calling this function, you must call cache_link_downloads on a list that includes the specified link.  Then you
must call get_cached_link_download on each member of the $links list passed to cache_link_downloads.

If the given link has already been cached, this function will return the result for that link.  If the given link
has not been cached, this function will use ParallellGet to cache the result for the requested link and the next
$LINK_CACHE_SIZE links in the $links list passed to cache_link_downloads.

Returns the decoded content of the http response for the given link.

=cut

sub get_cached_link_download
{
    my ( $link ) = @_;

    die( "no { _link_num } field in $link->{ url }: did you call cache_link_downloads? " )
      unless ( defined( $link->{ _link_num } ) );

    my $link_num = $link->{ _link_num };

    my $r = $_link_downloads_cache->{ $link_num };
    if ( defined( $r ) )
    {
        return ( ref( $r ) ? $r->decoded_content : $r );
    }

    my $links      = $_link_downloads_list;
    my $urls       = [];
    my $url_lookup = {};
    for ( my $i = 0 ; $links->[ $link_num + $i ] && $i < $LINK_CACHE_SIZE ; $i++ )
    {
        my $link = $links->[ $link_num + $i ];
        my $u    = URI->new( $link->{ _fetch_url } )->as_string;

        # handle duplicate urls within the same set of urls
        push( @{ $urls }, $u ) unless ( $url_lookup->{ $u } );
        push( @{ $url_lookup->{ $u } }, $link );

        $link->{ _cached_link_downloads }++;
    }

    my $responses = ParallelGet( $urls );

    $_link_downloads_cache = {};
    for my $response ( @{ $responses } )
    {
        my $original_url = MediaWords::Util::Web->get_original_request( $response )->uri->as_string;
        my $response_link_nums = [ map { $_->{ _link_num } } @{ $url_lookup->{ $original_url } } ];
        if ( !@{ $response_link_nums } )
        {
            WARN "NO LINK_NUM FOUND FOR URL '$original_url' ";
        }

        for my $response_link_num ( @{ $response_link_nums } )
        {
            if ( $response->is_success )
            {
                $_link_downloads_cache->{ $response_link_num } = $response;
            }
            else
            {
                DEBUG( "Error retrieving content for $original_url: " . $response->status_line );
                $_link_downloads_cache->{ $response_link_num } = '';
            }
        }
    }

    WARN "Unable to find cached download for '$link->{ url }'" if ( !defined( $_link_downloads_cache->{ $link_num } ) );

    my $response = $_link_downloads_cache->{ $link_num };
    return ( ref( $response ) ? $response->decoded_content : ( $response || '' ) );
}

=head2 get_cached_link_download_redirect_url( $link )

Get the redirected url from the cached download for the url. If no redirected url is found, just return the given url.

=cut

sub get_cached_link_download_redirect_url
{
    my ( $link ) = @_;

    my $url      = URI->new( $link->{ url } )->as_string;
    my $link_num = $link->{ _link_num };

    # make sure the $_link_downloads_cache is setup correctly
    get_cached_link_download( $link );

    if ( my $response = $_link_downloads_cache->{ $link_num } )
    {
        if ( $response && ref( $response ) )
        {
            return $response->request->uri->as_string;
        }
    }

    return $url;
}

=head2 response_error_is_client_side( $response )

Return true if the response's error was generated by LWP itself and not by the server.

=cut

sub response_error_is_client_side($)
{
    my $response = shift;

    if ( $response->is_success )
    {
        die "Response was successful, but I have expected an error.\n";
    }

    my $header_client_warning = $response->header( 'Client-Warning' );
    if ( defined $header_client_warning and $header_client_warning =~ /Internal response/ )
    {
        # Error was generated by LWP::UserAgent (created by
        # MediaWords::Util::Web::UserAgent); likely we didn't reach server
        # at all (timeout, unresponsive host, etc.)
        #
        # http://search.cpan.org/~gaas/libwww-perl-6.05/lib/LWP/UserAgent.pm#$ua->get(_$url_)
        return 1;
    }
    else
    {
        return 0;
    }
}

=head2 get_meta_refresh_url( $response, $url )


Given the response and request, parse the content for a meta refresh url and return if present. Otherwise,
return undef.

=cut

sub get_meta_refresh_url
{
    my ( $response, $url ) = @_;

    return undef unless ( $response->is_success );

    MediaWords::Util::URL::meta_refresh_url_from_html( $response->decoded_content, $url );
}

=head2 get_meta_redirect_response( $response, $url )

If thee response has a meta tag or is an archive url, parse out the original url and treat it as a redirect
by inserting it into the response chain.   Otherwise, just return the original response.

=cut

sub get_meta_redirect_response
{
    my ( $response, $url ) = @_;

    for my $f ( \&get_meta_refresh_url, \&get_original_url_from_archive_url )
    {
        my $redirect_url = $f->( $response, $url );
        next unless ( $redirect_url );

        my $redirect_response = UserAgent()->get( $redirect_url );
        $redirect_response->previous( $response );

        $response = $redirect_response;
    }

    return $response;
}

1;
