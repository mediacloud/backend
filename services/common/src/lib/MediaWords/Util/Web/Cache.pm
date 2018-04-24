package MediaWords::Util::Web::Cache;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;
use URI;

use MediaWords::Util::URL;
use MediaWords::Util::Web;

# list of downloads to precache downloads for
my $_link_downloads_list;

# precached link downloads
my $_link_downloads_cache;

# number of links to prefetch at a time for the cached downloads
Readonly my $LINK_CACHE_SIZE => 200;

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
        my $url          = $link->{ url };
        my $redirect_url = $link->{ redirect_url };

        $link->{ _link_num } = $i++;
        $link->{ _fetch_url } = $redirect_url || $url;
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

    my $url          = $link->{ url };
    my $redirect_url = $link->{ redirect_url };

    unless ( MediaWords::Util::URL::is_http_url( $url ) )
    {
        WARN "Not caching link because URL $url is invalid.";
        return '';
    }

    if ( $redirect_url and ( !MediaWords::Util::URL::is_http_url( $redirect_url ) ) )
    {
        WARN "Not caching link because redirect URL $redirect_url is invalid.";
        return '';
    }

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

        my $u = URI->new( $link->{ _fetch_url } )->as_string;

        unless ( MediaWords::Util::URL::is_http_url( $u ) )
        {
            WARN "Not caching link because URL $u is invalid.";
            next;
        }

        # handle duplicate urls within the same set of urls
        push( @{ $urls }, $u ) unless ( $url_lookup->{ $u } );
        push( @{ $url_lookup->{ $u } }, $link );

        $link->{ _cached_link_downloads }++;
    }

    my $ua        = MediaWords::Util::Web::UserAgent->new();
    my $responses = $ua->parallel_get( $urls );

    $_link_downloads_cache = {};
    for my $response ( @{ $responses } )
    {
        my $original_url = $response->original_request->url;
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

    my $url          = $link->{ url };
    my $redirect_url = $link->{ redirect_url };

    unless ( MediaWords::Util::URL::is_http_url( $url ) )
    {
        WARN "Not caching link because URL $url is invalid.";
        return $url;
    }

    if ( $redirect_url and ( !MediaWords::Util::URL::is_http_url( $redirect_url ) ) )
    {
        WARN "Not caching link because redirect URL $redirect_url is invalid.";
        return $url;
    }

    $url = URI->new( $link->{ url } )->as_string;

    my $link_num = $link->{ _link_num };

    # make sure the $_link_downloads_cache is setup correctly
    get_cached_link_download( $link );

    if ( my $response = $_link_downloads_cache->{ $link_num } )
    {
        if ( $response && ref( $response ) )
        {
            return $response->request->url;
        }
    }

    return $url;
}

1;
