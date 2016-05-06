package Feed::Scrape;

# scrape an html page for rss/rsf/atom feeds

use strict;
use warnings;

use Encode;
use Feed::Find;
use HTML::Entities;
use List::Util;
use URI::URL;
use URI::Escape;
use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::Util::URL;
use Domain::PublicSuffix;
use Carp;
use HTML::LinkExtractor;
use HTML::Entities;
use Readonly;

Readonly my $MAX_DEFAULT_FEEDS => 4;

#use XML::FeedPP;
use XML::LibXML;
use List::MoreUtils qw(any all none notall true false firstidx first_index
  lastidx last_index insert_after insert_after_string
  apply after after_incl before before_incl indexes
  firstval first_value lastval last_value each_array
  each_arrayref pairwise natatime mesh zip distinct uniq minmax);

use MediaWords::Util::Web;

use Data::Dumper;
use XML::FeedPP::MediaWords;

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
# Note: We consider just using Feed::Find from CPAN but didn't find it sufficent so we created Feed::Scrape
#
# Details:
# Feed::Find is much simpler and less effective than our Feed::Scrape stuff,
# mostly because Feed::Scrape is more inclusive but goes to the trouble of
# actually downloading anything that looks like it might be a feed to verify. We found it
# necessary to actually download the feeds to get any sort of accuracy in finding the feeds,
# albeit at the cost of downloading them.
#
# Note that Feed::Scrape uses the non-threaded, pseudo parallel fetching of just submitting a
# bunch of requests serially and then collecting the results from each request as each server responds.

# INTERNAL METHODS

# given a list of urls, return a list of feeds in the form of { name => $name, url => $url, feed_type => 'syndicated' }
# representing all of the links that refer to valid feeds (rss, rdf, or atom)
sub _validate_and_name_feed_urls
{
    my ( $class, $urls ) = @_;

    my $links = [];

    my $responses = MediaWords::Util::Web::ParallelGet( $urls );

    for my $response ( @{ $responses } )
    {
        if ( !$response->is_success )
        {
            DEBUG "Failed to get URL: " . $response->request->url . " with error: " . $response->status_line;
            next;
        }

        my $content = $response->decoded_content;

        my $url = MediaWords::Util::Web->get_original_request( $response )->url->as_string;

        DEBUG "Parsing $url";

        if ( my $feed = $class->parse_feed( $content ) )
        {
            push(
                @{ $links },
                {
                    name => $feed->title() || '',
                    url => $url,
                    feed_type => 'syndicated'
                }
            );
        }
    }

    return $links;
}

# resolve relative url if necessary
sub _resolve_relative_url
{
    my ( $class, $base_url, $url ) = @_;

    my $resolved_url = url( decode_entities( $url ) )->abs( $base_url )->as_string();

    #$c->log->debug("resolve_relative_url: $base_url + $url => $resolved_url");

    return $resolved_url;
}

# check whether the url passes various validity tests
sub _is_valid_feed_url
{
    my ( $class, $url ) = @_;

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

# METHODS

sub _fix_atom_content_element_encoding
{
    my $xml_string = shift @_;

    my $parser = XML::LibXML->new;
    my $doc;

    eval { $doc = $parser->parse_string( $xml_string ); };

    if ( $@ )
    {
        DEBUG "Error parsing feed string";
        return $xml_string;
    }

    my $doc_element = $doc->documentElement() || die;

    my $xpc = XML::LibXML::XPathContext->new;
    $xpc->registerNs( 'x', 'http://www.w3.org/2005/Atom' );
    my @content_nodes = $xpc->findnodes( '//x:entry/x:content', $doc_element )->get_nodelist;

    #either the feed is RSS or there is no content
    return $xml_string if scalar( @content_nodes ) == 0;

    my $fixed_content_element = 0;

    foreach my $content_node ( @content_nodes )
    {
        next if ( !$content_node->hasChildNodes() );

        my $child_nodes = $content_node->childNodes();

        my $child_node_count = $child_nodes->size;

        if ( $child_node_count == 1 )
        {
            my $first_child = $content_node->firstChild();

            next if ( $first_child->nodeType == XML_CDATA_SECTION_NODE );
            next if ( $first_child->nodeType == XML_TEXT_NODE );
        }

        my @content_node_child_list = $child_nodes->get_nodelist();

        # allow white space before CDATA_SECTION
        if ( any { $_->nodeType == XML_CDATA_SECTION_NODE } @content_node_child_list )
        {
            my @non_cdata_children = grep { $_->nodeType != XML_CDATA_SECTION_NODE } @content_node_child_list;

            if ( all { $_->nodeType == XML_TEXT_NODE } @non_cdata_children )
            {
                if ( all { $_->data =~ /\s+/ } @non_cdata_children )
                {
                    next;
                }
            }
        }

        $fixed_content_element = 1;

        my $child_nodes_string = join '', ( map { $_->toString() } ( $child_nodes->get_nodelist() ) );

        $content_node->removeChildNodes();

        my $cdata_node = XML::LibXML::CDATASection->new( $child_nodes_string );
        $content_node->appendChild( $cdata_node );
    }

    #just return the original string if we didn't need to fix anything...
    return $xml_string if !$fixed_content_element;

    my $ret = $doc->toString;

    #say "Returning :'$ret'";
    return $ret;
}

# parse feed with XML::FeedPP after some simple munging to correct feed formatting.
# return the XML::FeedPP feed object or undef if the parse failed.
sub parse_feed
{
    my ( $class, $content ) = @_;

    # fix content in various ways to make sure it will parse

    my $chunk = substr( $content, 0, 1024 );

    # make sure that there's some sort of feed id in the first chunk of the file
    if ( $chunk =~ /<html/i )
    {

        # warn "Feed not parsed -- contains '<html'";
        return undef;
    }

    if ( $chunk !~ /<(?:rss|feed|rdf)/i )
    {

        # warn "Feed not parsed -- missing feed tag in first 1024 characters";
        return undef;
    }

    # parser doesn't like files that start with comments
    $content =~ s/^<!--[^>]*-->\s*<\?/<\?/;

    # get rid of any cruft before xml tag that upsets parser
    $content =~ s/.{1,256}\<\?xml/\<\?xml/;

    $content = _fix_atom_content_element_encoding( $content );

    my $feed;

    #$DB::single = 1;
    eval { $feed = XML::FeedPP::MediaWords->new( { content => $content, type => 'string' } ) };

    if ( $@ )
    {
        DEBUG "parse feed failed";
        return undef;
    }
    else
    {
        return $feed;
    }
}

# give a list of urls, return a list of feeds in the form of { name => $name, url => $url, feed_type => 'syndicated' }
# representing all of the links that refer to valid feeds (rss, rdf, or atom).
sub get_valid_feeds_from_urls
{
    my ( $class, $urls ) = @_;

    if ( !$urls || !@{ $urls } )
    {
        return [];
    }

    my $url_hash;
    $urls = [ grep { !$url_hash->{ $_ }++ } @{ $urls } ];

    $urls = [ grep { $_ !~ /\.(gif|jpg|jpeg|png|css|js)$/i } @{ $urls } ];

    my $links = $class->_validate_and_name_feed_urls( $urls );

    my $u = {};
    map { $u->{ normalize_feed_url( $_->{ url } ) } = $_ } @{ $links };

    return [ sort { $a->{ name } cmp $b->{ name } } values( %{ $u } ) ];
}

# parse the html feed link tags
sub get_feed_urls_from_html_links
{
    my ( $class, $base_url, $html ) = @_;

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
                my $url = $class->_resolve_relative_url( $base_url, $1 );

                DEBUG "Match link: $url";
                push( @{ $urls }, $url );
            }
        }
    }

    my $r;
    return [ grep { !$r->{ $_ }++ } @{ $urls } ];
}

# look for a valid feed that is either a <link> tag or one of a
# set of standard feed urls based on the blog url
sub get_main_feed_urls_from_html($$$)
{
    my ( $class, $url, $html ) = @_;

    my $link_feed_urls = $class->get_feed_urls_from_html_links( $url, $html );

    my $valid_link_feeds = $class->get_valid_feeds_from_urls( $link_feed_urls );

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

    my $valid_feed_urls = $class->get_valid_feeds_from_urls( $standard_urls );

    $valid_feed_urls = [ $valid_feed_urls->[ 0 ] ] if ( @{ $valid_feed_urls } );

    return $valid_feed_urls;

}

# same as get_main_feed_urls_from_html(), just fetch the URL beforehand
sub get_main_feed_urls_from_url($$)
{
    my ( $class, $url ) = @_;

    my $response = MediaWords::Util::Web::ParallelGet( [ $url ] )->[ 0 ];

    return [] unless ( $response->is_success );

    my $html = $response->decoded_content;

    my $feeds = $class->get_main_feed_urls_from_html( $url, $html );

    return $feeds;
}

# parse the html for anything that looks like a feed url
sub get_feed_urls_from_html($$$)
{
    my ( $class, $base_url, $html ) = @_;

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

        my $quoted_url = $class->_resolve_relative_url( $base_url, $url );

        if ( $class->_is_valid_feed_url( $quoted_url ) )
        {
            DEBUG "Matched quoted URL: $quoted_url";
            push( @{ $urls }, $quoted_url );
        }
    }

    # look for unquoted urls
    while ( $html =~ m~href=([^ "'>]*(?:feed|rss|xml|syndication|sitemap|rdf|atom)[^ "'>]*)[ >]~gi )
    {
        my $unquoted_url = $class->_resolve_relative_url( $base_url, $1 );

        if ( $class->_is_valid_feed_url( $unquoted_url ) )
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
            my $quoted_url = $class->_resolve_relative_url( $base_url, $url );

            if ( $class->_is_valid_feed_url( $quoted_url ) )
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
sub _recurse_get_valid_feeds_from_index_url($$$$$$)
{
    my ( $class, $urls, $db, $ignore_patterns, $recurse_urls_to_skip, $recurse_levels_left ) = @_;

    carp '$urls must be a reference ' unless ref( $urls );

    $#{ $urls } = List::Util::min( $#{ $urls }, $MAX_INDEX_URLS - 1 );

    my $responses = MediaWords::Util::Web::ParallelGet( $urls );

    my $scraped_url_lookup = {};

    for my $response ( @{ $responses } )
    {
        my $feed_urls = $class->get_feed_urls_from_html( $response->request->url, $response->decoded_content );

        map { $scraped_url_lookup->{ $_ }++ } @{ $feed_urls };
    }

    # take into account a list of urls not to scrape
    map { delete( $scraped_url_lookup->{ $_ } ) } @{ $recurse_urls_to_skip };

    my $scraped_urls = [ keys( %{ $scraped_url_lookup } ) ];

    $#{ $scraped_urls } = List::Util::min( $#{ $scraped_urls }, $MAX_INDEX_URLS - 1 );

    my $valid_feeds = $class->get_valid_feeds_from_urls( $scraped_urls, $db, $ignore_patterns );

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
                    $class->_recurse_get_valid_feeds_from_index_url( $scraped_urls, $db, $ignore_patterns, $valid_feeds,
                        $recurse_levels_left )
                }
            );

            my $u = {};
            map { $u->{ normalize_feed_url( $_->{ url } ) } = $_ } @{ $valid_feeds };
            $valid_feeds = [ sort { $a->{ name } cmp $b->{ name } } values( %{ $u } ) ];
        }
    }

    return $valid_feeds;
}

# try to find all rss feeds for a site from the home page url of the site.  return a list
# of urls of found rss feeds.
#
# fetch the html for the page at the $index url.  call get_valid_feeds_from_urls on the
# urls scraped from that page.
sub get_valid_feeds_from_index_url($$$$$)
{
    my ( $class, $urls, $recurse, $db, $ignore_patterns ) = @_;

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

    return $class->_recurse_get_valid_feeds_from_index_url( $urls, $db, $ignore_patterns, [], $recurse_levels_left );
}

# return a normalized version of the feed to help avoid duplicate feeds
sub normalize_feed_url
{
    my ( $url ) = @_;

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
# Returns a hashref to the main feed ({name => '...', url => '...', feed_type => 'syndicated'}) if such feed exists,
# undef if it doesn't at all or 2+ such feeds exist
sub _main_feed_via_common_prefixed_feeds($)
{
    my ( $feed_links ) = @_;

    # If there's only one feed and it still has to be moderated, we should probably leave it that way
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
    my ( $host ) = @_;
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
    my ( $host ) = @_;
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

# "http://www.example.com/one/two/three.xml" -> "www.example.com"
sub _host_from_url($)
{
    my ( $url ) = @_;

    return lc( URI->new( $url )->host );
}

# return default feeds from the feed links passed as a parameter
# (might return an empty array if no links look like default feeds)
sub _default_feed_links($$)
{
    my ( $medium, $feed_links ) = @_;

    my $default_feed_links = [];

    my $medium_host                = _host_from_url( $medium->{ url } );                # e.g. "www.example.com"
    my $medium_second_level_domain = _second_level_domain_from_host( $medium_host );    # e.g. "example.com"
    my $medium_name                = _website_name_from_host( $medium_host );           # e.g. "example"

    # look through all feeds found for those with the host name in them and if found
    # treat them as default feeds
    foreach my $feed_link ( @{ $feed_links } )
    {
        my $feed_host                = _host_from_url( $feed_link->{ url } );
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
sub _immediate_redirection_url_for_medium($$)
{
    my ( $db, $medium ) = @_;

    my $ua       = MediaWords::Util::Web::UserAgent();
    my $response = $ua->get( $medium->{ url } );

    my $new_url = $response->request->uri->as_string || '';
    if ( $new_url and $medium->{ url } ne $new_url )
    {
        DEBUG "New medium URL via HTTP redirect: $medium->{url} => $new_url";
        return $new_url;
    }

    my $html = $response->decoded_content || '';
    $new_url = MediaWords::Util::URL::meta_refresh_url_from_html( $html );
    if ( $new_url and $medium->{ url } ne $new_url )
    {
        DEBUG "New medium URL via HTML <meta/> refresh: $medium->{url} => $new_url";
        return $new_url;
    }

    return undef;
}

# Add default feeds for the media by searching for them in the index page, then (if not found)
# in a couple of child pages
sub get_feed_links_and_need_to_moderate($$)
{
    my ( $db, $medium ) = @_;

    # if the website's main URL has been changed to a new one, update the URL to the new one
    # (don't touch the database though)
    my $new_url_after_redirect = _immediate_redirection_url_for_medium( $db, $medium );
    if ( $new_url_after_redirect )
    {
        $medium->{ url } = $new_url_after_redirect;
    }

    # first look for <link> feeds or a set of url pattern feeds that are likely to be
    # main feeds if present (like "$url/feed")
    my $default_feed_links = Feed::Scrape->get_main_feed_urls_from_url( $medium->{ url } );

    # otherwise do an expansive search
    my $feed_links;
    my $need_to_moderate;
    if ( scalar @{ $default_feed_links } == 0 )
    {
        $need_to_moderate = 1;
        $feed_links =
          Feed::Scrape::MediaWords->get_valid_feeds_from_index_url( [ $medium->{ url } ], 1, $db, [] );

        $default_feed_links = _default_feed_links( $medium, $feed_links );
    }

    # if there are more than 0 default feeds, use those.  If there are no more than
    # $MAX_DEFAULT_FEEDS, use the first one and don't moderate.
    if ( scalar @{ $default_feed_links } > 0 )
    {
        $default_feed_links = [ sort { length( $a->{ url } ) <=> length( $b->{ url } ) } @{ $default_feed_links } ];
        if ( scalar @{ $default_feed_links } <= $MAX_DEFAULT_FEEDS )
        {
            $default_feed_links = [ $default_feed_links->[ 0 ] ];
        }
        $feed_links       = $default_feed_links;
        $need_to_moderate = 0;
    }

    # If no feeds were found, add the 'web_page' feed to the feed-less website and don't moderate
    if ( scalar @{ $feed_links } == 0 )
    {
        push(
            @{ $feed_links },
            {
                name      => $medium->{ name },
                url       => $medium->{ url },
                feed_type => 'web_page'
            }
        );
        $need_to_moderate = 0;
    }

    return ( $feed_links, $need_to_moderate );
}

1;
