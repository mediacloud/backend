#!/usr/bin/env perl
#
# Fetch Facebook page links from a list of Facebook pages
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2013";
use MediaWords::CommonLibs;
use MediaWords::Util::Facebook;
use MediaWords::Util::URL;

use Getopt::Long;
use File::Slurp;
use Scalar::Util qw/looks_like_number/;
use Data::Dumper;

# Returns true of Open Graph object belongs to a Facebook page
# (https://developers.facebook.com/docs/graph-api/reference/page)
sub _is_facebook_page($)
{
    my $og_object = shift;

    # If Facebook page doesn't exist, API will return stats for an URL as if it
    # was just a basic, non-Facebook URL
    if ( defined $og_object->{ og_object } )
    {
        return 0;
    }
    else
    {
        return 1;
    }
}

sub fetch_facebook_page_links($)
{
    my $facebook_page_url = shift;

    say STDERR "Fetching stats for Facebook page URL $facebook_page_url";

    $facebook_page_url = MediaWords::Util::URL::normalize_url( $facebook_page_url );
    say STDERR "\tNormalized page URL: $facebook_page_url";

    # Fetch Open Graph object
    my $og_object = MediaWords::Util::Facebook::api_request( '', [ { key => 'id', value => $facebook_page_url } ] );
    unless ( _is_facebook_page( $og_object ) )
    {
        say STDERR "URL $facebook_page_url is not a Facebook page";
    }
    else
    {
        my $og_object_id = $og_object->{ id };
        unless ( defined $og_object_id )
        {
            die "Object ID for URL $facebook_page_url is undefined.";
        }
        unless ( looks_like_number( $og_object_id ) )
        {
            die "Object ID for URL $facebook_page_url does not look like a number.";
        }
        $og_object_id = $og_object_id + 0;
        say STDERR "\tOpen Graph object ID: $og_object_id";

        # # Fetch page's feed
        my $feed = MediaWords::Util::Facebook::api_request( $og_object_id . '/feed', [] );
        unless ( defined( $feed->{ data } ) )
        {
            die "Feed object doesn't have 'data' key.";
        }
        unless ( defined( $feed->{ paging } ) )
        {
            die "Feed object doesn't have 'paging' key.";
        }

    }
}

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );
    $| = 1;

    Readonly my $usage => <<EOF;
Usage: $0 --pages_file facebook-pages.txt
EOF

    my $pages_file;
    Getopt::Long::GetOptions( "pages_file=s" => \$pages_file, ) or die $usage;
    die $usage unless ( $pages_file );

    my @page_urls = split( /\r?\n/, read_file( $pages_file ) );

    foreach my $page_url ( @page_urls )
    {
        if ( $page_url )
        {
            fetch_facebook_page_links( $page_url );
        }
    }
}

main();
