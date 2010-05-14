#!/usr/bin/perl

# scrape the list of nytimes topics

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use strict;

use MediaWords::Util::Web;
use MediaWords::Util::StopWords;

#<font []^>]><a href="http://topics.nytimes.com/top/reference/timestopics/people/a/aaliyah/index.html">Aaliyah</a><br></font>

sub fetch_topics
{
    my ( $urls ) = @_;

    my $topics = {};

    my $responses = MediaWords::Util::Web::ParallelGet( $urls );

    for my $response ( @{ $responses } )
    {

        if ( !$response->is_success() )
        {
            print STDERR "Unable to fetch url " . $response->request->url . ": " . $response->status_line() . "\n";
            next;
        }

        my $html = $response->content();

        while (
            $html =~ m~<font[^>]*><a href="([^"]*http://topics.nytimes.com/top/[^"]+/index.html)">([^<]+)</a><br></font>~g )
        {

            my ( $url, $topic ) = ( $1, $2 );

            if ( $url =~ m~(people|companies|organizations|countries|usstates)~ )
            {

                if ( $url =~ m~timestopics/people~ )
                {
                    if ( !( $topic =~ s/(.*), (.*)( [A-Z]\.)/$2 $1/ ) )
                    {
                        $topic =~ s/(.*), (.*)/$2 $1/;
                    }
                }

                $topic =~ s/ \(.*\)$//;

                $topics->{ lc( $topic ) } = 1;
            }
        }
    }

    return [ keys( %{ $topics } ) ];
}

sub get_wayback_urls
{
    my $wayback_urls;
    for my $letter ( 'a' .. 'z' )
    {
        push(
            @{ $wayback_urls },
            "http://web.archive.org/web/*/http://topics.nytimes.com/top/reference/timestopics/all/$letter/index.html"
        );
    }

    my $responses = MediaWords::Util::Web::ParallelGet( $wayback_urls );

    my $nyt_urls;
    for my $response ( @{ $responses } )
    {
        if ( !$response->is_success() )
        {
            print STDERR "Unable to fetch url " . $response->request->url . ": " . $response->status_line() . "\n";
            return;
        }

        my $html = $response->content();

        while ( $html =~
            m~(http://web.archive.org/web/[0-9]+/http://topics.nytimes.com/top/reference/timestopics/all/[a-z]/index.html)~g
          )
        {
            push( @{ $nyt_urls }, $1 );
        }
    }

    return $nyt_urls;
}

sub main
{
    my ( $option ) = @ARGV;

    my $topics = {};

    my $all_urls;

    if ( $option eq '-a' )
    {
        $all_urls = get_wayback_urls();
    }

    for my $letter ( 'a' .. 'z' )
    {
        push( @{ $all_urls }, "http://topics.nytimes.com/top/reference/timestopics/all/$letter/index.html" );
    }

    my $topics = fetch_topics( $all_urls );

    my $stop_word_lookup = MediaWords::Util::StopWords::get_long_stop_word_lookup();
    $stop_word_lookup->{ homer } = 1;
    $stop_word_lookup->{ queen } = 1;

    my $stopped_topics;
    for my $topic ( @{ $topics } )
    {
        if ( !$stop_word_lookup->{ $topic } )
        {
            push( @{ $stopped_topics }, $topic );
        }
    }

    print join( "\n", sort @{ $stopped_topics } ) . "\n";
}

main();
