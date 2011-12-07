package MediaWords::Crawler::Pager;
use MediaWords::CommonLibs;


# module for finding the next page link in a page of html content

use strict;

use HTML::Entities;
use URI::Split;
use URI::URL;

# INTERNAL FUNCTIONS

# given a full url, get the base directory
# so http://foo.bar/foobar/foo/bar?foo=bar returns http://foo.bar/foobar/foo
sub _get_url_base
{
    my ( $url ) = @_;

    if ( $url !~ m~^([^\?]*/[^\?/]*)/[^\?/]*/?(\?.*)?$~i )
    {
        return $url;
    }

    #print "url_base: $1\n";

    return $1;
}

# use a variety of texts to guess whether a given link is a link to a next page
sub _link_is_next_page
{
    my ( $raw_url, $full_url, $text, $base_url ) = @_;

    # TODO: remove any trailing '?' from both base and full url
    if ( $full_url eq $base_url )
    {
        return 0;
    }

    if ( $raw_url =~ /^(?:#|javascript)/ )
    {
        return 0;
    }

    if ( $text =~ /(.*)<img[^>]+alt=["']([^"']*)['"][^>]*>(.*)/is )
    {
        my $stripped_text = "$1 $3";
        my $alt           = $2;

        if ( $stripped_text !~ /\w/ )
        {
            $text = $alt;

            #print "alt text: $text\n";
        }
    }

    # look for the word 'next' with at most one word before and two words after or just the > character
    if ( $text !~ /^\s*(?:(?:\s*[^\s]+\s+)?next(?:\s+[^\s]+\s*){0,2}|\&gt\;)\s*$/is )
    {
        return 0;
    }

    # these indicate that the next link goes to the next story rather than the next page
    if ( $text =~ /(?:in|photo|story|topic)/is )
    {
        return 0;
    }

    # match the parent directories of the two urls
    if ( _get_url_base( $full_url ) ne _get_url_base( $base_url ) )
    {
        return 0;
    }

    #print "link is next page: true (" . join('|', @_) . ")\n";
    return 1;
}

# METHODS

# look for a 'next page' link in the give html content and return the associated link if found
sub get_next_page_url
{
    my ( $class, $validate_sub, $base_url ) = @_;

    my $content_ref = \$_[ 3 ];

    say STDERR "Starting get_next_page_url";

    # blogs and forums almost never have paging but often have 'next' story / thread links
    if ( $base_url =~ /blog|forum|discuss/ )
    {
        return;
    }

    #print "content: $_[2]\n";

    my $url;

    my $content_length = length( $$content_ref );

    say STDERR "Starting get_next_page_url content_length: $content_length";

    while ( $$content_ref =~ /<a\s/isog )
    {
        my $pos = $-[0];
        my $len;

        if ( substr( $$content_ref, $pos ) !~ m~</a[^\w]~iso )
        {
            $len = $content_length - $pos;
        }
        else {
            $len = $-[0];
        }

        if ( !( substr( $$content_ref, $pos, $len ) =~ m~<a[^>]+href=["']([^"']*)["'][^>]*>(.*)~iso ) )
        {
            next;
        }

        my $raw_url = $1;
        my $text    = $2;
        
        my $full_url = lc( url( decode_entities( $raw_url ) )->abs( $base_url )->as_string() );

        if ( _link_is_next_page( $raw_url, $full_url, $text, $base_url ) && !$validate_sub->( $full_url ) )
        {
            $url = $full_url;
        
            #print "found next page: $url [$text]\n";
        }
    }
    
    if ( $url )
    {
        return url( decode_entities( $url ) )->abs( $base_url )->as_string();
    }
    else
    {
        return undef;
    }
}

1;
