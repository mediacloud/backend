package MediaWords::Crawler::Pager;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

=head1 NAME

Mediawords::Crawler::Pager - given an html page, return any urls that lead to the next page of content

=head1 SYNOPSIS

    my $url = get_next_page_url( { return 1 }, 'http://www.nytimes.com/2016/02/01/trump.html', $content );

=head1 DESCRIPTION

This module parses an html page and returns the first link that looks like a 'next page' link for a multi-page
story.  It tries to ignore links that lead to a next comment, a next category, or some other next thing.

=cut

use strict;

use HTML::Entities;
use URI::Split;
use URI::URL;

=head1 FUNCTIONS

=cut

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

my $regex_match_count = 0;
my $regex_tried_count = 0;

# use a variety of tests to guess whether a given link is a link to a next page
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

    $regex_tried_count++;

    ## This if statement is redundant but is needed for performance reasons on Perl 5.8.
    if ( ( $text =~ /.*<img[^>].*/is ) && ( $text =~ /.*<img[^>]+alt=["'][^"']*['"][^>]*>.*/is ) )
    {
        if ( $text =~ /(.*)<img[^>]+alt=["']([^"']*)['"][^>]*>(.*)/is )
        {
            my $stripped_text = "$1 $3";
            my $alt           = $2;

            $regex_match_count++;

            # say "Slow regex matched. match_count $regex_match_count / $regex_tried_count. text length: " . length( $text );

            if ( $stripped_text !~ /\w/ )
            {
                $text = $alt;

                #print "alt text: $text\n";
            }
        }
    }

    # look for the word 'next' with at most one word before and two words after or just the > character
    if ( $text !~ /^\s*(?:(?:\s*[^\s]+\s+)?next(?:\s+[^\s]+\s*){0,2}|\&gt\;)\s*$/is )
    {
        return 0;
    }

    # these indicate that the next link goes to the next story rather than the next page
    if ( $text =~ /(?:in|photo|story|topic|article)/is )
    {
        return 0;
    }

    # match the parent directories of the two urls
    if ( _get_url_base( $full_url ) ne _get_url_base( $base_url ) )
    {
        return 0;
    }

    return 1;
}

=head2 get_next_page_url( $validate_sub, $base_url, $content )

Look for a 'next page' link in the give html content and return the associated link if found. Use $base_url as the base
for any relative urls found.  Call $validate_sub->( $full_url ) on each full url found and only return the url
if the call returns true.

=cut

sub get_next_page_url
{
    my ( $validate_sub, $base_url ) = @_;

    my $content_ref = \$_[ 3 ];

    # blogs and forums almost never have paging but often have 'next' story / thread links
    if ( $base_url =~ /blog|forum|discuss|wordpress|livejournal/ )
    {
        return;
    }

    #print "content: $_[2]\n";

    my $url;

    my $content_length = bytes::length( $$content_ref );

    while ( $$content_ref =~ /<a\s/isog )
    {
        my $pos = $-[ 0 ];
        my $len;

        if ( substr( $$content_ref, $pos ) !~ m~</a[^\w]~iso )
        {
            $len = $content_length - $pos;
        }
        else
        {
            $len = $-[ 0 ];
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
