package MediaWords::Feed::Scrape;

# scrape an html page for rss/rsf/atom feeds

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Feed::Parse;
use MediaWords::Util::ParseHTML;
use MediaWords::Util::URL;
use MediaWords::Util::Web;

use Data::Dumper;
use Domain::PublicSuffix;
use Encode;
use HTML::Entities;
use HTML::LinkExtractor;
use List::MoreUtils qw/distinct/;
use List::Util;
use Readonly;
use URI::Escape;
use URI::URL;

Readonly my $MAX_DEFAULT_FEEDS => 4;

# max urls that get_valid_feeds_from_index_url will fetch
Readonly my $MAX_INDEX_URLS => 1000;

# max length of scraped urls
Readonly my $MAX_SCRAPED_URL_LENGTH => 256;

# max number of recursive calls to _recurse_get_valid_feeds_from_index_url()
Readonly my $MAX_RECURSE_LEVELS => 1;

# list of url patterns to ignore
Readonly my @URL_IGNORE_PATTERNS => (
    qr|add\.my\.yahoo\.com|i,        #
    qr|login\.|i,                    #
    qr|fusion\.google\.com/add|i,    #
    qr|gif|i,                        #
    qr|jpg|i,                        #
    qr|png|i,                        #
    qr|xml:lang|i,                   #
    qr|feedback|i,                   #
    qr|error|i,                      #
    qr|digg\.com|i,                  #
    qr|bloglines|i,                  #
    qr|doubleclick|i,                #
    qr|classified|i,                 #
);

#
# Note: We consider just using Feed::Find from CPAN but didn't find it sufficent so we created MediaWords::Feed::Scrape
#
# Details:
# Feed::Find is much simpler and less effective than our MediaWords::Feed::Scrape stuff,
# mostly because MediaWords::Feed::Scrape is more inclusive but goes to the trouble of
# actually downloading anything that looks like it might be a feed to verify. We found it
# necessary to actually download the feeds to get any sort of accuracy in finding the feeds,
# albeit at the cost of downloading them.
#

# INTERNAL METHODS

# given a list of urls, return a list of feeds in the form of { name => $name, url => $url, type => 'syndicated' }
# representing all of the links that refer to valid feeds (rss, rdf, or atom)
sub _validate_and_name_feed_urls
{
    my $urls = shift;

    my $links = [];

    $urls = [ grep { MediaWords::Util::URL::is_http_url( $_ ) } @{ $urls } ];

    my $ua        = MediaWords::Util::Web::UserAgent->new();
    my $responses = $ua->parallel_get( $urls );

    for my $response ( @{ $responses } )
    {
        if ( !$response->is_success )
        {
            DEBUG "Failed to get URL: " . $response->request->url . " with error: " . $response->status_line;
            next;
        }

        my $content = $response->decoded_content;

        my $url = $response->original_request->url;

        DEBUG "Parsing $url";

        if ( my $feed = MediaWords::Feed::Parse::parse_feed( $content ) )
        {
            push(
                @{ $links },
                {
                    name => $feed->title() || '',
                    url  => $url,
                    type => 'syndicated'
                }
            );
        }
    }

    return $links;
}

# resolve relative url if necessary
sub _resolve_relative_url($$)
{
    my ( $base_url, $url ) = @_;

    my $resolved_url = url( decode_entities( $url ) )->abs( $base_url )->as_string();

    #$c->log->debug("resolve_relative_url: $base_url + $url => $resolved_url");

    return $resolved_url;
}

# check whether the url passes various validity tests
sub _is_valid_feed_url($)
{
    my $url = shift;

    if ( length( $url ) > $MAX_SCRAPED_URL_LENGTH )
    {
        return 0;
    }

    if ( grep { $url =~ $_ } @URL_IGNORE_PATTERNS )
    {
        return 0;
    }

    return MediaWords::Util::URL::is_http_url( $url );
}

# parse the html feed link tags
sub _get_feed_urls_from_html_links($$)
{
    my ( $base_url, $html ) = @_;

    my $url_hash = {};

    my $urls = [];

    # get all <link>s (no matter whether they're RSS links or not)
    while ( $html =~ m~(<\s*?link.+?>)~gi )
    {
        my $link = $1;

        # filter out RSS / Atom links
        if ( $link =~ m~application/rss\+xml~i or $link =~ m~application/atom\+xml~i or $link =~ m~text/xml~i )
        {
            if ( $link =~ m~href\s*=\s*["']([^"']*)["']~i )
            {
                my $url = _resolve_relative_url( $base_url, $1 );

                if ( MediaWords::Util::URL::is_http_url( $url ) )
                {
                    DEBUG "Match link: $url";
                    push( @{ $urls }, $url );
                }
            }
        }
    }

    my $r;
    return [ grep { !$r->{ $_ }++ } @{ $urls } ];
}

# look for a valid feed that is either a <link> tag or one of a
# set of standard feed urls based on the blog url
sub _get_main_feed_urls_from_html($$)
{
    my ( $url, $html ) = @_;

    my $link_feed_urls = _get_feed_urls_from_html_links( $url, $html );

    my $valid_link_feeds = get_valid_feeds_from_urls( $link_feed_urls );

    return $valid_link_feeds if ( @{ $valid_link_feeds } );

    my $suffixes = [

        # Generic suffixes
        'index.xml',  'atom.xml',     'feeds',                'feeds/default',
        'feed',       'feed/default', 'feeds/posts/default/', '?feed=rss',
        '?feed=atom', '?feed=rss2',   '?feed=rdf',            'rss',
        'atom',       'rdf',          'index.rss',

        # Typo3 RSS URL
        '?type=100',

        # Joomla RSS URL
        '?format=feed&type=rss',

        # Blogger.com RSS URL
        'feeds/posts/default',

        # LiveJournal RSS URL
        'data/rss',

        # Posterous.com RSS feed
        'rss.xml',

        # Patch.com RSS feeds
        'articles.rss',
        'articles.atom',
    ];

    my $chopped_url = $url;
    chop( $chopped_url ) if ( $url =~ /\/$/ );

    my $standard_urls = [ map { "${ chopped_url }/$_" } @{ $suffixes } ];

    my $valid_feed_urls = get_valid_feeds_from_urls( $standard_urls );

    $valid_feed_urls = [ $valid_feed_urls->[ 0 ] ] if ( @{ $valid_feed_urls } );

    return $valid_feed_urls;

}

# same as _get_main_feed_urls_from_html(), just fetch the URL beforehand
sub _get_main_feed_urls_from_url($)
{
    my $url = shift;

    unless ( MediaWords::Util::URL::is_http_url( $url ) )
    {
        LOGCONFESS "URL is not HTTP(s): $url";
    }

    my $ua = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->parallel_get( [ $url ] )->[ 0 ];

    return [] unless ( $response->is_success );

    my $html = $response->decoded_content;

    my $feeds = _get_main_feed_urls_from_html( $url, $html );

    return $feeds;
}

# parse the html for anything that looks like a feed url
sub _get_feed_urls_from_html($$)
{
    my ( $base_url, $html ) = @_;

    # If <base href="..." /> is present, use that instead of the base URL passed as a parameter
    if ( $html =~ m|<\s*?base\s+?href\s*?=\s*?["'](http://.+?)["']|i )
    {
        DEBUG "Changing base URL from $base_url to $1";
        $base_url = $1;
    }

    my $url_hash = {};

    my $urls = [];

    my $p = HTML::LinkExtractor->new( undef, $base_url );
    $p->parse( \$html );
    my $links = [ grep { lc( $_->{ tag } ) eq 'a' } @{ $p->links } ];

    $links = [ grep { lc( $_->{ href }->scheme ) eq 'http' } @{ $links } ];

    # Match only the links that look like RSS links
    # ('_TEXT' is something like '<a href="http://perl.com/"> I am a LINK!!! </a>')
    $links = [ grep { $_->{ _TEXT } =~ /feed|rss|syndication|sitemap|xml|rdf|atom|subscrib/i } @{ $links } ];

    my $link_urls = [ map { $_->{ href } } @{ $links } ];
    $link_urls = [ map { $_->as_string } @{ $link_urls } ];

    # Remove news aggregator URLs from potential feeds
    for ( @{ $link_urls } )
    {
        my $match_count = 0;
        $match_count = $match_count + s|^http://www\.google\.com/ig/add\?feedurl=(http://.+?)$|$1|;
        $match_count = $match_count + s|^http://add\.my\.yahoo\.com/rss\?url=(http://.+?)$|$1|;
        $match_count = $match_count + s|^http://add\.my\.yahoo\.com/content\?lg=en&url=(http://.+?)$|$1|;
        $match_count = $match_count + s|^http://www\.netvibes\.com/subscribe\.php\?url=(http://.+?)$|$1|;
        $match_count = $match_count + s|^http://fusion\.google\.com/add\?feedurl=(http://.+?)$|$1|;
        $match_count = $match_count + s|^http://www\.wikio\.com/subscribe\?url=(http://.+?)$|$1|;
        $match_count = $match_count + s|^http://www\.bloglines\.com/sub/(http://.+?)$|$1|;
        $match_count = $match_count + s|^http://newsgator\.com/ngs/subscriber/subext\.aspx\?url=(http://.+?)$|$1|;

        if ( $match_count )
        {
            $_ = uri_unescape( $_ );
        }

        # Remove "?format=html" for FeedBurner links (e.g. on http://www.eldis.org/go/subscribe, elsewhere too)
        s|^(http://feeds\d*?\.feedburner\.com/.+?)\?format=html$|$1|;
    }

    push( @{ $urls }, @{ $link_urls } );

    # look for quoted urls
    while ( $html =~ m~["']([^"']*(?:feed|rss|syndication|sitemap|xml|rdf|atom|subscrib)[^"']*)["']~gi )
    {
        my $url = $1;

        #Remove trailing backslash
        $url =~ s/(.*)\\/$1/;

        my $quoted_url = _resolve_relative_url( $base_url, $url );

        if ( _is_valid_feed_url( $quoted_url ) )
        {
            DEBUG "Matched quoted URL: $quoted_url";
            push( @{ $urls }, $quoted_url );
        }
    }

    # look for unquoted urls
    while ( $html =~ m~href=([^ "'>]*(?:feed|rss|xml|syndication|sitemap|rdf|atom)[^ "'>]*)[ >]~gi )
    {
        my $unquoted_url = _resolve_relative_url( $base_url, $1 );

        if ( _is_valid_feed_url( $unquoted_url ) )
        {
            DEBUG "Matched unquoted URL: $unquoted_url";
            push( @{ $urls }, $unquoted_url );
        }
    }

    # look for unlinked urls
    my $unlinked_urls = MediaWords::Util::URL::http_urls_in_string( $html );
    foreach my $url ( @{ $unlinked_urls } )
    {
        if ( $url =~ m~feed|rss|xml|syndication|sitemap|rdf|atom~gi )
        {
            my $quoted_url = _resolve_relative_url( $base_url, $url );

            if ( _is_valid_feed_url( $quoted_url ) )
            {
                DEBUG "Matched unlinked URL: $quoted_url";
                push( @{ $urls }, $quoted_url );
            }
        }
    }

    $urls = [ distinct @{ $urls } ];
    return $urls;
}

# (recursive helper)
#
# try to find all rss feeds for a site from the home page url of the site.  return a list
# of urls of found rss feeds.
#
# fetch the html for the page at the $index url.  call get_valid_feeds_from_urls on the
# urls scraped from that page.
sub _recurse_get_valid_feeds_from_index_url($$$$);    # prototype to be able to recurse

sub _recurse_get_valid_feeds_from_index_url($$$$)
{
    my ( $urls, $ignore_patterns, $recurse_urls_to_skip, $recurse_levels_left ) = @_;

    LOGCARP '$urls must be a reference ' unless ref( $urls );

    $#{ $urls } = List::Util::min( $#{ $urls }, $MAX_INDEX_URLS - 1 );

    $urls = [ grep { MediaWords::Util::URL::is_http_url( $_ ) } @{ $urls } ];

    my $ua        = MediaWords::Util::Web::UserAgent->new();
    my $responses = $ua->parallel_get( $urls );

    my $scraped_url_lookup = {};

    for my $response ( @{ $responses } )
    {
        my $feed_urls = _get_feed_urls_from_html( $response->request->url, $response->decoded_content );

        map { $scraped_url_lookup->{ $_ }++ } @{ $feed_urls };
    }

    # take into account a list of urls not to scrape
    map { delete( $scraped_url_lookup->{ $_ } ) } @{ $recurse_urls_to_skip };

    my $scraped_urls = [ keys( %{ $scraped_url_lookup } ) ];

    $#{ $scraped_urls } = List::Util::min( $#{ $scraped_urls }, $MAX_INDEX_URLS - 1 );

    my $valid_feeds = get_valid_feeds_from_urls( $scraped_urls, $ignore_patterns );

    if ( scalar @{ $scraped_urls } > 0 )
    {
        if ( $recurse_levels_left > 0 )
        {
            map { delete( $scraped_url_lookup->{ $_->{ url } } ) } @{ $valid_feeds };
            $scraped_urls = [ keys( %{ $scraped_url_lookup } ) ];

            $recurse_levels_left = $recurse_levels_left - 1;
            push(
                @{ $valid_feeds },
                @{
                    _recurse_get_valid_feeds_from_index_url( $scraped_urls, $ignore_patterns, $valid_feeds,
                        $recurse_levels_left )
                }
            );

            my $u = {};
            map { $u->{ _normalize_feed_url( $_->{ url } ) } = $_ } @{ $valid_feeds };
            $valid_feeds = [ sort { $a->{ name } cmp $b->{ name } } values( %{ $u } ) ];
        }
    }

    return $valid_feeds;
}

# return a normalized version of the feed to help avoid duplicate feeds
sub _normalize_feed_url($)
{
    my $url = shift;

    $url = lc( $url );

    # remove multiple formats of the same feed
    $url =~ s/(atom|rdf|xml|feed|application)/rss/g;

    # after multiple format normalization, treat http://cnn.com/feed/rss and http://cnn.com/feed as duplicates
    $url =~ s/rss\/rss/rss/g;

    # if there are really long cgi params, it's more likely to be junk
    $url =~ s/(\?.{32,})//;

    # remove tailing slashes
    $url =~ s/\/+$//;

    return $url;
}

# If the feeds share a common prefix, e.g.:
#
# * Example.com
# * Example.com - Economy
# * Example.com - Finance
# * Example.com - Sports
# * Example.com - Entertainment
#
# then assume that the first feed is the "main" feed containing all the stories.
#
# Returns a hashref to the main feed ({name => '...', url => '...', type => 'syndicated'}) if such feed exists,
# undef if it doesn't at all or 2+ such feeds exist
sub _main_feed_via_common_prefixed_feeds($)
{
    my $feed_links = shift;

    # If there's only one feed, we should probably leave it that way
    if ( scalar @{ $feed_links } == 1 )
    {
        return undef;
    }

    # Check if the feed names are reasonably long
    foreach my $link ( @{ $feed_links } )
    {
        if ( length( $link->{ name } ) < 4 )
        {
            return undef;
        }
    }

    # Find common prefix
    my $feed_names = [ map { $_->{ name } } @{ $feed_links } ];

    @_ = @{ $feed_names };
    my $prefix = shift;
    for ( @_ )
    {
        chop $prefix while ( !/^\Q$prefix\E/ );
    }

    # Prefix is of reasonable length?
    if ( length( $prefix ) < 4 )
    {

        return undef;
    }

    # Prefix exactly matches exactly one of the feed links
    my $match_count = 0;
    my $link_found;
    foreach my $link ( @{ $feed_links } )
    {
        if ( $link->{ name } eq $prefix )
        {
            ++$match_count;
            $link_found = $link;
        }
    }
    if ( $match_count != 1 )
    {
        return undef;
    }

    return $link_found;
}

# "subdomain.example.com" => "example.com"
sub _second_level_domain_from_host($)
{
    my $host = shift;
    my $domain;

    if ( $host =~ /^[a-zA-Z.]+$/ and $host =~ /\./ )
    {

        # Full-blown domain name
        my $suffix = Domain::PublicSuffix->new();
        $domain = $suffix->get_root_domain( $host );
    }
    else
    {

        # IP or "localhost"
        $domain = $host;
    }

    return $domain;
}

# "www.example.com" -> "example"
sub _website_name_from_host($)
{
    my $host = shift;
    my $domain;

    if ( $host =~ /^[a-zA-Z.]+$/ and $host =~ /\./ )
    {

        # Full-blown domain name
        my $suffix = Domain::PublicSuffix->new();
        $domain = $suffix->get_root_domain( $host );
        my $tld = $suffix->suffix();

        $domain =~ s/(.+?)\.$tld$/$1/i;
    }
    else
    {

        # IP or "localhost"
        $domain = $host;
    }

    return $domain;
}

# return default feeds from the feed links passed as a parameter
# (might return an empty array if no links look like default feeds)
sub _default_feed_links($$)
{
    my ( $medium, $feed_links ) = @_;

    my $default_feed_links = [];

    my $medium_host                = MediaWords::Util::URL::get_url_host( $medium->{ url } );    # e.g. "www.example.com"
    my $medium_second_level_domain = _second_level_domain_from_host( $medium_host );             # e.g. "example.com"
    my $medium_name                = _website_name_from_host( $medium_host );                    # e.g. "example"

    # look through all feeds found for those with the host name in them and if found
    # treat them as default feeds
    foreach my $feed_link ( @{ $feed_links } )
    {
        my $feed_host                = MediaWords::Util::URL::get_url_host( $feed_link->{ url } );
        my $feed_second_level_domain = _second_level_domain_from_host( $feed_host );

        if ( $feed_link->{ url } !~ /foaf/ )
        {
            if (

                # "www.example.com" == "www.example.com"
                ( $feed_host eq $medium_host ) or

                # "apple.example.com" == "pear.example.com" (not for blogs or comments)
                (
                        $feed_second_level_domain eq $medium_second_level_domain
                    and $feed_link !~ /(blog|social|comment|dis[cq]uss|forum|talk)/
                )
              )
            {
                push( @{ $default_feed_links }, $feed_link );
            }
        }
    }

    # Feed proxy URLs with media name in it should also be proclaimed as "default"
    # (FeedBurner and http://www.kevinmuldoon.com/feedburner-alternatives/)
    foreach ( @{ $feed_links } )
    {

        if (

            # http://feeds.feedburner.com/thesartorialist
            $_->{ url } =~ m|^http://feeds\d*?\.feedburner\.com/$medium_name.*?$|i or

            # http://quotidianohome.feedsportal.com/c/33327/f/565663/index.rss
            $_->{ url } =~ m|^http://$medium_name.*?\.feedsportal\.com.*?$|i or

            # http://feeds.feedblitz.com/thehappyhousewife-full-feed
            $_->{ url } =~ m|^http://feeds\.feedblitz\.com/$medium_name.*?$|i or

            # http://feed.feedcat.net/lisour-Lb
            $_->{ url } =~ m|^http://feed\.feedcat\.net/$medium_name.*?$|i or

            # http://feeds.rapidfeeds.com/50292/
            $_->{ url } =~ m|^http://feeds\.rapidfeeds\.com/$medium_name.*?$|i or

            # http://feedity.com/tivo-com/VlNQUlRb.rss
            $_->{ url } =~ m|^http://feedity\.com/$medium_name.*?$|i
          )
        {
            push( @{ $default_feed_links }, $_ );
        }
    }

    $default_feed_links = [ distinct @{ $default_feed_links } ];

    # Check if feeds contain a common prefix; if so, extract the main feed from that list
    if ( scalar @{ $default_feed_links } > 0 )
    {
        my $main_feed = _main_feed_via_common_prefixed_feeds( $default_feed_links );
        if ( $main_feed )
        {
            $default_feed_links = [ $main_feed ];
        }
    }

    return $default_feed_links;
}

# If the URL gets immediately redirected to a new location (via HTTP headers),
# return the URL it gets redirected to.
# Returns undef if there's no such redirection
sub _immediate_redirection_url_for_medium($)
{
    my $medium = shift;

    my $ua       = MediaWords::Util::Web::UserAgent->new();
    my $response = $ua->get( $medium->{ url } );

    my $new_url = $response->request->url;
    if ( $new_url and ( !MediaWords::Util::URL::urls_are_equal( $medium->{ url }, $new_url ) ) )
    {
        DEBUG "New medium URL via HTTP redirect: $medium->{url} => $new_url";
        return $new_url;
    }

    my $html = $response->decoded_content || '';
    $new_url = MediaWords::Util::ParseHTML::meta_refresh_url_from_html( $html );
    if ( $new_url and ( !MediaWords::Util::URL::urls_are_equal( $medium->{ url }, $new_url ) ) )
    {
        DEBUG "New medium URL via HTML <meta/> refresh: $medium->{url} => $new_url";
        return $new_url;
    }

    return undef;
}

# try to find all rss feeds for a site from the home page url of the site.  return a list
# of urls of found rss feeds.
#
# fetch the html for the page at the $index url.  call get_valid_feeds_from_urls on the
# urls scraped from that page.
sub get_valid_feeds_from_index_url($$;$)
{
    my ( $urls, $recurse, $ignore_patterns ) = @_;

    my $recurse_levels_left;
    if ( $recurse )
    {

        # Run recursively with up to $MAX_RECURSE_LEVELS
        $recurse_levels_left = $MAX_RECURSE_LEVELS;
    }
    else
    {

        # Run only once (non-recursively)
        $recurse_levels_left = 0;
    }

    return _recurse_get_valid_feeds_from_index_url( $urls, $ignore_patterns, [], $recurse_levels_left );
}

# give a list of urls, return a list of feeds in the form of { name => $name, url => $url, type => 'syndicated' }
# representing all of the links that refer to valid feeds (rss, rdf, or atom).
# ignore urls that match one of the ignore patterns
sub get_valid_feeds_from_urls($;$)
{
    my ( $urls, $ignore_patterns_string ) = @_;

    if ( !$urls || !@{ $urls } )
    {
        return [];
    }

    $ignore_patterns_string = '' unless ( defined( $ignore_patterns_string ) );

    my $ignore_patterns = [ split( ' ', $ignore_patterns_string ) ];

    my $pruned_urls = [];
    for my $url ( @{ $urls } )
    {
        if ( grep { index( lc( $url ), lc( $_ ) ) > -1 } @{ $ignore_patterns } )
        {
            next;
        }

        push( @{ $pruned_urls }, $url );
    }
    $urls = $pruned_urls;

    my $url_hash;
    $urls = [ grep { !$url_hash->{ $_ }++ } @{ $urls } ];

    $urls = [ grep { $_ !~ /\.(gif|jpg|jpeg|png|css|js)$/i } @{ $urls } ];

    my $links = _validate_and_name_feed_urls( $urls );

    my $u = {};
    map { $u->{ _normalize_feed_url( $_->{ url } ) } = $_ } @{ $links };

    return [ sort { $a->{ name } cmp $b->{ name } } values( %{ $u } ) ];
}

# Get default feeds for the media by searching for them in the index page, then (if not found)
# recursively in child pages
sub get_feed_links($)
{
    my $medium = shift;

    return [] if ( !MediaWords::Util::URL::is_http_url( $medium->{ url } ) );

    # if the website's main URL has been changed to a new one, update the URL to the new one
    # (don't touch the database though)
    my $new_url_after_redirect = _immediate_redirection_url_for_medium( $medium );
    if ( $new_url_after_redirect )
    {
        $medium->{ url } = $new_url_after_redirect;
    }

    # first look for <link> feeds or a set of url pattern feeds that are likely to be
    # main feeds if present (like "$url/feed")
    my $default_feed_links = _get_main_feed_urls_from_url( $medium->{ url } );

    # otherwise do an expansive search
    my $feed_links;
    if ( scalar @{ $default_feed_links } == 0 )
    {
        $feed_links = get_valid_feeds_from_index_url( [ $medium->{ url } ], 1, [] );

        $default_feed_links = _default_feed_links( $medium, $feed_links );
    }

    # if there are more than 0 default feeds, use those.  If there are no more than
    # $MAX_DEFAULT_FEEDS, use the first one.
    if ( scalar @{ $default_feed_links } > 0 )
    {
        $default_feed_links = [ sort { length( $a->{ url } ) <=> length( $b->{ url } ) } @{ $default_feed_links } ];
        if ( scalar @{ $default_feed_links } <= $MAX_DEFAULT_FEEDS )
        {
            $default_feed_links = [ $default_feed_links->[ 0 ] ];
        }
        $feed_links = $default_feed_links;
    }

    # If no feeds were found, add the 'web_page' feed to the feed-less website
    if ( scalar @{ $feed_links } == 0 )
    {
        push(
            @{ $feed_links },
            {
                name => $medium->{ name },
                url  => $medium->{ url },
                type => 'web_page'
            }
        );
    }

    return $feed_links;
}

1;
