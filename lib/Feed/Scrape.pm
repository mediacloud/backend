package Feed::Scrape;

# scrape an html page for rss/rsf/atom feeds

use strict;

use Encode;
use Feed::Find;
use HTML::Entities;
use List::Util;
use Regexp::Common qw /URI/;
use URI::URL;
use Modern::Perl "2012";
use MediaWords::CommonLibs;
use Carp;
use HTML::LinkExtractor;

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
use constant MAX_INDEX_URLS => 1000;

# max length of scraped urls
use constant MAX_SCRAPED_URL_LENGTH => 256;

# list of url patterns to ignore
use constant URL_IGNORE_PATTERNS => (
    'add.my.yahoo.com', 'login.',   'fusion.google.com/add', 'gif',      'jpg',       'png',
    'xml:lang',         'feedback', 'error',                 'digg.com', 'bloglines', 'doubleclick',
    'classified'
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

# STATICS

my $_verbose = 0;

my $_feed_find_domains = [
    qw/24open.ru damochka.ru babyblog.ru ya.ru mail.ru privet.ru
      liveinternet.ru rambler.ru mylove.ru i.ua diary.ru livejournal.com/
];

# INTERNAL METHODS

# return true if the url is from one of the domains in $_feed_find_domains
sub _is_feed_find_url
{
    my ( $url ) = @_;

    $url =~ m~^https?://(?:[^/]*\.)?([^\./]*\.[^\/]*)(/.*)?~;

    my $domain = $1;

    return grep { $_ eq $domain } @{ $_feed_find_domains };
}

sub _log_message
{
    my @args = @_;

    if ( $_verbose )
    {
        warn( @args );
    }
}

# given a list of urls, return a list of feeds in the form of { name => $name, url => $url }
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
            _log_message( "failed to get url: " . $response->request->url . " with error: " . $response->status_line );
            next;
        }

        my $content = $response->decoded_content;

        my $url = MediaWords::Util::Web->get_original_request( $response )->url;

        say STDERR "Parsing $url";

        if ( my $feed = $class->parse_feed( $content ) )
        {
            push( @{ $links }, { name => $feed->title() || '', url => $url } );
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
sub _is_valid_url
{
    my ( $class, $url ) = @_;

    if ( length( $url ) > MAX_SCRAPED_URL_LENGTH )
    {
        return 0;
    }

    if ( grep { $url =~ /$_/i } URL_IGNORE_PATTERNS )
    {
        return 0;
    }

    if ( $url !~ /$RE{URI}/ )
    {
        return 0;
    }

    if ( $url !~ /^https?/i )
    {
        return 0;
    }

    return 1;
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
        say STDERR "Error parsing feed string";
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

                    #say STDERR "Skipping CDATA and white space only description ";
                    #exit;
                    next;
                }
            }
        }

        $fixed_content_element = 1;

        # say STDERR "fixing content_node: " . $content_node->toString;
        # say Dumper ( [ $child_nodes->get_nodelist() ] );
        # say Dumper ( [ map { $_->toString } $child_nodes->get_nodelist() ] );

        my $child_nodes_string = join '', ( map { $_->toString() } ( $child_nodes->get_nodelist() ) );

        $content_node->removeChildNodes();

        my $cdata_node = XML::LibXML::CDATASection->new( $child_nodes_string );
        $content_node->appendChild( $cdata_node );

        #say STDERR "fixed content_node: " . $content_node->toString;
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
        warn "Feed not parsed -- contains '<html'";
        return undef;
    }

    if ( $chunk !~ /<(?:rss|feed|rdf)/i )
    {
        warn "Feed not parsed -- missing feed tag in first 1024 characters";
        return undef;
    }

    # parser doesn't like files that start with comments
    $content =~ s/^<!--[^>]*-->\s*<\?/<\?/;

    $content = _fix_atom_content_element_encoding( $content );

    my $feed;

    #$DB::single = 1;
    eval { $feed = XML::FeedPP::MediaWords->new( { content => $content, type => 'string' } ) };

    if ( $@ )
    {
        say STDERR "Parsed Feed failed";

        #say dump( $feed );

        return undef;
    }
    else
    {
        return $feed;
    }
}

# give a list of urls, return a list of feeds in the form of { name => $name, url => $url }
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

    #_log_message("scrape html: $html");

    my $urls = [];
    while ( $html =~ m~<link[^>]*type=.?application/rss\+xml.?[^>]*>~gi )
    {
        my $link = $1;
        if ( $link =~ m~href=["']([^"']*)["']~i )
        {
            my $url = $class->_resolve_relative_url( $base_url, $1 );

            _log_message( "match link: $url" );
            push( @{ $urls }, $url );
        }
    }

    my $r;
    return [ grep { !$r->{ $_ }++ } @{ $urls } ];
}

# parse the html for anything that looks like a feed url
sub get_feed_urls_from_html
{
    my ( $class, $base_url, $html ) = @_;

    # say STDERR "get_feed_urls_from_html";

    my $url_hash = {};

    #_log_message("scrape html: $html");

    my $urls = [];

    my $p = HTML::LinkExtractor->new( undef, $base_url );
    $p->parse( \$html );
    my $links = [ grep { $_->{ tag } eq 'a' } @{ $p->links } ];

    $links = [ grep { $_->{ href }->scheme eq 'http' } @{ $links } ];

    my $link_urls = [ map { $_->{ href } } @{ $links } ];

    $link_urls = [ grep { $_->as_string =~ /feed|rss|syndication|sitemap|xml|rdf|atom/ } @{ $link_urls } ];

    # say STDERR "Dumping link_urls";
    # say STDERR Dumper ( $link_urls );

    push( @{ $urls }, @{ $link_urls } );

    # look for quoted urls
    while ( $html =~ m~["']([^"']*(?:feed|rss|syndication|sitemap|xml|rdf|atom)[^"']*)["']~gi )
    {
        my $url = $1;

        #Remove trailing backslash
        $url =~ s/(.*)\\/\1/;

        my $quoted_url = $class->_resolve_relative_url( $base_url, $url );

        if ( $class->_is_valid_url( $quoted_url ) )
        {
            _log_message( "matched quoted url: $quoted_url" );
            push( @{ $urls }, $quoted_url );
        }
    }

    # look for unquoted urls
    while ( $html =~ m~href=([^ "'>]*(?:feed|rss|xml|syndication|sitemap|rdf|atom)[^ "'>]*)[ >]~gi )
    {
        my $unquoted_url = $class->_resolve_relative_url( $base_url, $1 );

        if ( $class->_is_valid_url( $unquoted_url ) )
        {
            _log_message( "matched unquoted url: $unquoted_url" );
            push( @{ $urls }, $unquoted_url );
        }
    }

    $urls = [ distinct @{ $urls } ];
    return $urls;
}

# combination of get_feeds_urls_from_html and get_valid_feeds_from_urls
sub get_valid_feeds_from_html
{

    my $class    = shift( @_ );
    my $base_url = shift( @_ );
    my $html     = shift( @_ );

    my $urls = $class->get_feed_urls_from_html( $base_url, $html );

    return $class->get_valid_feeds_from_urls( $urls, @_ );
}

# if there's only a single urls and we recognize the url as a bloghost for which feed::find will work,
# use that (to avoid the very expensive recursion and validation involved below).
#
#  Otherwise fallback back on get_valid_feeds_from_index_url below
#
sub get_valid_feeds_from_single_index_url
{
    my $class   = shift( @_ );
    my $url     = shift( @_ );
    my $recurse = shift( @_ );

    carp '$url must be a string ' unless scalar $url;

    if ( _is_feed_find_url( $url ) )
    {
        return $class->get_valid_feeds_from_urls( [ Feed::Find->find( $url ) ], @_ );
    }

    my $urls = [ $url ];

    return $class->get_valid_feeds_from_index_url( $urls, $recurse, @_ );
}

# try to find all rss feeds for a site from the home page url of the site.  return a list
# of urls of found rss feeds.
#
# fetch the html for the page at the $index url.  call get_valid_feeds_from_urls on the
# urls scraped from that page.
#
# TODO: Refactor and clean up this function so it's more readable. It's only called in a couple of places so changing it should be relatively safe
#  Variables such as $recurse should have consistent type, and not be used for multiple purposes. (Currently $recurse can be either a boolean or a reference to an array of strings.
# Ideally there would be a private implementation function that does the actual recursion that is called by a short non-recurvsive public function
# 
#
sub get_valid_feeds_from_index_url
{
    my $class   = shift( @_ );
    my $urls    = shift( @_ );
    my $recurse = shift( @_ );

    # say STDERR 'get_valid_feeds_from_index_url';
    # say Dumper( $urls );

    carp '$urls must be a reference ' unless ref( $urls );

    $#{ $urls } = List::Util::min( $#{ $urls }, MAX_INDEX_URLS - 1 );

    my $responses = MediaWords::Util::Web::ParallelGet( $urls );

    my $scraped_url_lookup = {};

    for my $response ( @{ $responses } )
    {
        my $feed_urls = $class->get_feed_urls_from_html( $response->request->url, $response->decoded_content );

        # say STDERR "Got the following urls from " .  $response->request->url . ":" . Dumper( $feed_urls );

        map { $scraped_url_lookup->{ $_ }++ } @{ $feed_urls };
    }

    # if recurse is a ref, use it as a list of urls not to scrape and the undef it so that we don't recurse further
    if ( ref( $recurse ) )
    {
        map { delete( $scraped_url_lookup->{ $_ } ) } @{ $recurse };
        $recurse = undef;
    }

    my $scraped_urls = [ keys( %{ $scraped_url_lookup } ) ];
    $#{ $scraped_urls } = List::Util::min( $#{ $scraped_urls }, MAX_INDEX_URLS - 1 );

    my $valid_feeds = $class->get_valid_feeds_from_urls( $scraped_urls, @_ );

    if ( $recurse )
    {
        map { delete( $scraped_url_lookup->{ $_->{ url } } ) } @{ $valid_feeds };
        $scraped_urls = [ keys( %{ $scraped_url_lookup } ) ];

        push( @{ $valid_feeds }, @{ $class->get_valid_feeds_from_index_url( $scraped_urls, $valid_feeds, @_ ) } );

        my $u = {};
        map { $u->{ normalize_feed_url( $_->{ url } ) } = $_ } @{ $valid_feeds };
        $valid_feeds = [ sort { $a->{ name } cmp $b->{ name } } values( %{ $u } ) ];
    }

    return $valid_feeds;
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

1;
