#!/usr/bin/perl

# scrape gv posts for a list of hostnames that appear in urls
#
# input is a text file in the format:
# url,
# country, country, ...
#
# output is in the form
# hostname,country,country_count,country,country_count,...

use strict;
use LWP::UserAgent::Determined;

sub get_post_hosts
{
    my ( $post ) = @_;

    my $ua = LWP::UserAgent::Determined->new;
    $ua->timing( "10,30,90" );
    my $response = $ua->get( $post );

    if ( $response->is_error )
    {
        print STDERR "ERROR: " . $response->as_string . "\n";
        return [];
    }

    my $html = $response->content;

    if (   !( $html =~ /<div id="full-article">(.*)<div class="postfooter/ms )
        && !( $html =~ /<div id="full-article">(.*)<div class="recent-articles">/ms ) )
    {
        warn( "Unable to parse post $post" );
        return [];
    }

    my $article_html = $1;

    my $hosts = {};

    while ( $article_html =~ m~https?://([^/'"]+)~g )
    {
        my $host = lc( $1 );

        $host =~ s/^www.//;

        $hosts->{ $host } = 1;
    }

    return [ keys( %{ $hosts } ) ];
}

sub main
{
    binmode STDOUT, "utf8";
    binmode STDERR, "utf8";

    my $hostnames = {};

    while ( my $post = <> )
    {
        chop( $post );
        chop( $post );

        my $countries = <>;
        chomp( $countries );
        my $countries = [ split( ', ', $countries ) ];

        my $blank = <>;

        print STDERR "post: $post\n";
        my $post_hosts = get_post_hosts( $post );
        print STDERR "hosts: " . join( ", ", @{ $post_hosts } ) . "\n";

        for my $post_host ( @{ $post_hosts } )
        {
            for my $country ( @{ $countries } )
            {
                $hostnames->{ $post_host }->{ $country }++;
            }
        }
    }

    while ( my ( $hostname, $countries ) = each( %{ $hostnames } ) )
    {
        print "$hostname,";
        while ( my ( $country, $count ) = each( %{ $countries } ) )
        {
            print "$country,$count,";
        }
        print "\n";
    }
}

main();
