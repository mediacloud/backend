package Feed::Scrape;

# scrape an html page for rss/rsf/atom feeds

use strict;

use HTML::Entities;
use URI::URL;
use XML::FeedPP;

use MediaWords::Util::Web;

#
#Note: We consider just using Feed::Find from CPAN but didn't find it sufficent so we created Feed::Scrape
#
#Details:
#Feed::Find is much simpler and less effective than our Feed::Scrape stuff, 
#mostly because Feed::Scrape is more inclusive but goes to the trouble of 
#actually downloading anything that looks like it might be a feed to verify. We found it 
#necessary to actually download the feeds to get any sort of accuracy in finding the feeds,
# albeit at the cost of downloading them.
#
#Note that Feed::Scrape uses the non-threaded, pseudo parallel fetching of just submitting a 
#bunch of requests serially and then collecting the results from each request as each server responds.



# STATICS

# INTERNAL METHODS

# give a list of urls, return a list of feeds in the form of { name => $name, url => $url }
# representing all of the links that refer to valid feeds (rss, rdf, or atom)
sub _validate_and_name_feed_urls
{
    my ( $class, $urls ) = @_;

    my $links = [];

    my $responses = MediaWords::Util::Web::ParallelGet($urls);

    for my $response ( @{$responses} )
    {
        my $request = $response->request;

        if ( !$response->is_success )
        {
            warn("failed to get url: " . $response->request->url . " with error: " . $response->status_line);
            next;
        }

        my $content = $response->content;

        # parsing the xml is slow, so try parsing just a little bit before parsing the whole thing
        for my $length ( 1000, length($content) )
        {
            if ( my $feed = $class->parse_feed( substr( $content, 0, $length ) ) )
            {
                push( @{$links}, { name => $feed->title() || '', url => $request->url } );
                last;
            }
            else
            {
                warn( "failed to parse url " . $request->url . ": " . substr( $@, 0, 80 ) );
            }
        }
    }

    return $links;
}

# resolve relative url if necessary
sub _resolve_relative_url
{
    my ( $class, $base_url, $url ) = @_;

    my $resolved_url = url( decode_entities($url) )->abs($base_url)->as_string();
    
    #$c->log->debug("resolve_relative_url: $base_url + $url => $resolved_url");

    return $resolved_url;
}

# METHODS

# parse feed with XML::FeedPP after some simple munging to correct feed formatting.
# return the XML::FeedPP feed object or undef if the parse failed.
sub parse_feed
{
    my ( $class, $content ) = @_;

    # fix content in various ways to make sure it will parse
    # make sure that the feed has at least one newline so that feedpp will recognize it as content instead of url
    $content =~ s/\?\>/?>\n/g;
    $content =~ s/^<!--[^>]*-->\s*<\?/<\?/;

    my $feed;
    eval { $feed = XML::FeedPP->new($content) };
    if ($@)
    {
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

    if ( !$urls || !@{$urls} )
    {
        return [];
    }

    my $url_hash;
    $urls = [ grep { !$url_hash->{$_}++ } @{$urls} ];

    $urls = [ grep { $_ !~ /\.(gif|jpg|jpeg|png|css|js)/i } @{$urls} ];

    my $links = $class->_validate_and_name_feed_urls($urls);

    return [ sort { $a->{name} cmp $b->{name} } @{$links} ];
}

# parse the html for application/rss+xml link tags
sub get_feed_urls_from_html_links
{
    my ( $class, $base_url, $html ) = @_;

    my $url_hash = {};

    #warn("scrape html: $html");

    my $urls = [];
    while ( $html =~ m~<link[^>]*type=.?application/rss\+xml.?[^>]*>~gi )
    {
        my $link = $1;
        if ( $link =~ m~href=["']([^"']*)["']~i )
        {
            my $url = $class->_resolve_relative_url( $base_url, $1 );
            warn("match link: $url");
            push( @{$urls}, $url);
        }
    }

    my $r;
    return [ grep { !$r->{$_}++ } @{$urls} ];
}

# parse the html for anything that looks like a feed url
sub get_feed_urls_from_html
{
    my ( $class, $base_url, $html ) = @_;

    my $url_hash = {};

    #warn("scrape html: $html");

    my $urls = [];
    while ( $html =~ m~["']([^"']*(?:feed|rss|xml|rdf|atom)[^"']*)["']~gi )
    {
        my $quoted_url = $class->_resolve_relative_url( $base_url, $1 );
        warn("matched quoted url: $quoted_url");
        push( @{$urls}, $quoted_url );
    }

    #<a href=http://blog.al.com/jdcrowe/atom.xml>
    while ( $html =~ m~href=([^ "'>]*(?:feed|rss|xml|rdf|atom)[^ "'>]*)[ >]~gi )
    {
        my $unquoted_url = $class->_resolve_relative_url( $base_url, $1 );
        warn("matched unquoted url: $unquoted_url");
        push( @{$urls}, $unquoted_url );
    }

    my $r;
    return [ grep { !$r->{$_}++ } @{$urls} ];
}

# combination of get_feeds_urls_from_html and get_valid_feeds_from_urls
sub get_valid_feeds_from_html
{

    my $class    = shift(@_);
    my $base_url = shift(@_);
    my $html     = shift(@_);

    my $urls = $class->get_feed_urls_from_html( $base_url, $html );

    return $class->get_valid_feeds_from_urls( $urls, @_ );
}

# fetch the html for the page at the $index url.  call get_valid_feeds_from_urls on the
# urls scraped from that page.
sub get_valid_feeds_from_index_url
{

    my $class = shift(@_);
    my $url   = shift(@_);

    my $responses = MediaWords::Util::Web::ParallelGet( [$url] );
    my $response = $responses->[0];

    my $scraped_urls = $class->get_feed_urls_from_html( $url, $response->content );

    return $class->get_valid_feeds_from_urls( $scraped_urls, @_ );
}

1;
