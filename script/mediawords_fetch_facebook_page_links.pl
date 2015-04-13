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
use List::MoreUtils qw/uniq/;
use Readonly;
use URI;
use URI::QueryParam;
use Data::Dumper;

# Max. number of Facebook feed posts to process; 0 for no limit
Readonly my $FACEBOOK_MAX_POSTS_TO_PROCESS => 100;

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

sub _process_facebook_post($)
{
    my $post = shift;

    my @links;

    my $post_type = $post->{ type };
    unless ( defined $post_type )
    {
        die "Post type is undefined.";
    }

    my $post_status_type = $post->{ status_type };
    unless ( defined $post_status_type )
    {
        die "Post status type is undefined.";
    }

    my $post_link = $post->{ link };
    if ( $post_link )
    {
        my $skip_adding_post_link = 0;

        # Ignore cases when page posts photos from its own Facebook's album
        if ( $post_type eq 'photo' and $post_status_type eq 'added_photos' )
        {
            $skip_adding_post_link = 1;
        }

        # Ignore cases when page posts photos from some other page
        if ( $post_type eq 'photo' and $post_status_type eq 'shared_story' )
        {
            $skip_adding_post_link = 1;
        }

        unless ( $skip_adding_post_link )
        {
            push( @links, $post_link );
        }
    }

    my $post_message = $post->{ message };
    if ( $post_message )
    {
        my $message_links = MediaWords::Util::URL::http_urls_in_string( $post_message );
        foreach my $message_link ( @{ $message_links } )
        {
            push( @links, $message_link );
        }
    }

    @links = uniq @links;

    if ( scalar @links )
    {
        say STDERR "Links in post: " . Dumper( \@links );
    }
}

sub fetch_facebook_page_links($)
{
    my $facebook_page_url = shift;

    say STDERR "Fetching stats for Facebook page URL $facebook_page_url";

    $facebook_page_url = MediaWords::Util::URL::normalize_url( $facebook_page_url );
    say STDERR "\tNormalized page URL: $facebook_page_url";

    say STDERR "\tFetching Open Graph object...";
    my $og_object = MediaWords::Util::Facebook::api_request( '', [ { key => 'id', value => $facebook_page_url } ] );
    unless ( _is_facebook_page( $og_object ) )
    {
        warn "URL $facebook_page_url is not a Facebook page\n";
        return;
    }

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

    my $posts_processed = 0;
    my $posts;
    my $paging_next_url    = undef;
    my $page_being_fetched = 0;

    do
    {
        my $api_request_params;

        if ( $paging_next_url )
        {
            # Copy parameters from the "next" URL into a parameter arrayref
            my $paging_next_uri = URI->new( $paging_next_url );
            foreach my $param_name ( $paging_next_uri->query_param )
            {
                foreach my $param_value ( $paging_next_uri->query_param( $param_name ) )
                {
                    push(
                        @{ $api_request_params },
                        {
                            key   => $param_name,
                            value => $param_value,
                        }
                    );
                }
            }
        }
        else
        {
            $api_request_params = [];
        }

        ++$page_being_fetched;
        say STDERR "\tFetching page's $og_object_id feed (page $page_being_fetched)...";

        my $feed = MediaWords::Util::Facebook::api_request( $og_object_id . '/feed', $api_request_params );
        unless ( defined( $feed->{ data } ) and ref( $feed->{ data } ) eq ref( [] ) )
        {
            die "Feed object doesn't have 'data' key of the value is not an arrayref.";
        }

        $posts = $feed->{ data };
        if ( defined( $feed->{ paging } ) and ref( $feed->{ paging } ) eq ref( {} ) )
        {
            $paging_next_url = $feed->{ paging }->{ next };
        }
        else
        {
            $paging_next_url = undef;
        }

        foreach my $post ( @{ $posts } )
        {
            _process_facebook_post( $post );

            ++$posts_processed;
            if ( $posts_processed >= $FACEBOOK_MAX_POSTS_TO_PROCESS )
            {
                last;
            }
        }

      } while (

        # There's a "next page" URL returned by the API
        $paging_next_url

        and (
            # Either no limit, or
            $FACEBOOK_MAX_POSTS_TO_PROCESS == 0

            # ... didn't hit the limit yet
            or $posts_processed < $FACEBOOK_MAX_POSTS_TO_PROCESS
        )

        # Last page had posts
        and scalar( @{ $posts } ) > 0
      );

    say STDERR "\tProcessed $posts_processed posts.";
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
