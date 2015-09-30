package MediaWords::Util::Web;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

# various functions to make downloading web pages easier and faster, including parallel
# and cached fetching.

use strict;

use File::Temp;
use FindBin;
use LWP::UserAgent;
use LWP::UserAgent::Determined;
use HTTP::Status qw(:constants);
use Storable;
use Readonly;

use MediaWords::Util::Paths;
use MediaWords::Util::Config;

Readonly my $MAX_DOWNLOAD_SIZE => 1024 * 1024;
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

);

# list of downloads to precache downloads for
my $_link_downloads_list;

# precached link downloads
my $_link_downloads_cache;

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

    return $ua;
}

# return a user agent with media cloud default settings
sub UserAgent
{
    my $ua = LWP::UserAgent->new();
    return _set_lwp_useragent_properties( $ua );
}

# return a "determined" (retrying) user agent with media cloud default settings
sub UserAgentDetermined
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

            my $message = "Trying $url..., ";
            $message .=
              "will " . ( defined $duration ? "retry after $duration seconds" : "give up" ) . " if request fails...";
            say STDERR $message;
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
                $message .= "will " .
                  ( $will_retry ? ( defined $duration ? "retry after $duration seconds" : "give up" ) : "not retry" );
                say STDERR $message;
            }
        }
    );

    return _set_lwp_useragent_properties( $ua );
}

sub get_original_url_from_momento_archive_url
{
    my ( $archive_site_url ) = @_;
    my $ua                   = MediaWords::Util::Web::UserAgent();
    my $response             = $ua->get( $archive_site_url );

    my $link_header = $response->headers()->{ link };

    my @urls = ( $link_header =~ /\<(http[^>]*)\>/g );

    my $original_url = $urls[ 0 ];

    return $original_url;
}

# simple get for a url using the UserAgent above. return the decoded content
# if the response is successful and undef if not.
sub get_decoded_content
{
    my ( $url ) = @_;

    my $ua = UserAgent();

    my $res = $ua->get( $url );

    return $res->is_success ? $res->decoded_content : undef;
}

# get urls in parallel by using an external, forking script.
# we use this approach because LWP is not thread safe and
# LWP::Parallel::User is not fully parallel and no longer
# works with modern LWP in any case.
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

    my $mc_script_path = MediaWords::Util::Paths::mc_script_path();
    my $cmd            = "'$mc_script_path'/../script/mediawords_web_store.pl";

    #say STDERR "opening cmd:'$cmd' ";

    if ( !open( CMD, '|-', $cmd ) )
    {
        warn( "Unable to start $cmd: $!" );
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

# walk back from the given response to get the original request that generated the response.
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

# cache link downloads $LINK_CACHE_SIZE at a time so that we can do them in parallel.
# this doesn't actually do any caching -- it just sets the list of
# links so that they can be done $LINK_CACHE_SIZE at a time by get_cached_link_download.
sub cache_link_downloads
{
    my ( $links ) = @_;

    $_link_downloads_list = $links;

    my $i = 0;
    for my $link ( @{ $links } )
    {
        $link->{ _link_num } = $i++;
        $link->{ _fetch_url } = $link->{ redirect_url } || $link->{ url };
    }
}

# if the url has been precached, return it, otherwise download the current links and the next $LINK_CACHE_SIZE links
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
            warn( "NO LINK_NUM FOUND FOR URL '$original_url' " );
        }

        for my $response_link_num ( @{ $response_link_nums } )
        {
            if ( $response->is_success )
            {
                $_link_downloads_cache->{ $response_link_num } = $response;
            }
            else
            {
                my $msg = "error retrieving content for $original_url: " . $response->status_line;
                warn( $msg );
                $_link_downloads_cache->{ $response_link_num } = $msg;
            }
        }
    }

    warn( "Unable to find cached download for '$link->{ url }'" ) if ( !defined( $_link_downloads_cache->{ $link_num } ) );

    my $response = $_link_downloads_cache->{ $link_num };
    return ( ref( $response ) ? $response->decoded_content : ( $response || '' ) );
}

# get the redirected url from the cached download for the url.
# if no redirected url is found, just return the given url.
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

# Return true if the response's error was generated by LWP itself and not by
# the server
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

# given the response and request, parse the content for a meta refresh url and return if present.
# otherwise, return undef
sub get_meta_refresh_url
{
    my ( $response, $request ) = @_;

    return undef unless ( $response->is_success );

    MediaWords::Util::URL::meta_refresh_url_from_html( $response->decoded_content, $request->{ url } );
}

# if the response has a meta refresh tag, fetch the meta refresh content and
# insert the response into the redirect response chain as a normal redirect
sub get_meta_refresh_response
{
    my ( $response, $request ) = @_;

    my $meta_refresh_url = get_meta_refresh_url( $response, $request );

    return $response unless ( $meta_refresh_url );

    my $ua = UserAgent;

    my $meta_refresh_response = $ua->get( $meta_refresh_url );

    $meta_refresh_response->previous( $response );

    return $meta_refresh_response;
}

1;
