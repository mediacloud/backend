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

use Modern::Perl "2015";
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
use DBI;
use DBD::SQLite;

# Max. number of Facebook feed posts to process; 0 for no limit
Readonly my $FACEBOOK_MAX_POSTS_TO_PROCESS => 200;

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

sub _links_in_facebook_post($)
{
    my $post = shift;

    my @links;

    my $post_type = $post->{ type };
    unless ( defined $post_type )
    {
        die "Post type is undefined.";
    }

    my $post_status_type = $post->{ status_type } // '';

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

    # Fetch comments from the first chunk only
    my $post_comments = $post->{ comments }->{ data };
    if ( $post_comments )
    {
        unless ( ref( $post_comments ) eq ref( [] ) )
        {
            die "Comments is not an arrayref.";
        }

        foreach my $comment ( @{ $post_comments } )
        {
            my $comment_message       = $comment->{ message };
            my $comment_message_links = MediaWords::Util::URL::http_urls_in_string( $comment_message );
            foreach my $comment_message_link ( @{ $comment_message_links } )
            {
                push( @links, $comment_message_link );
            }
        }
    }

    @links = uniq @links;

    if ( scalar @links )
    {
        say STDERR "Links in post: " . Dumper( \@links );
    }

    return \@links;
}

sub fetch_facebook_page_links($$)
{
    my ( $facebook_page_url, $sqlite3_dbh ) = @_;

    my $sth;

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

    # Upsert the Facebook page URL
    $sth = $sqlite3_dbh->prepare(
        <<EOF
        INSERT OR IGNORE INTO facebook_pages (page_url) VALUES (?)
EOF
    );
    $sth->bind_param( 1, $facebook_page_url );
    $sth->execute();

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
            my $links = _links_in_facebook_post( $post );
            if ( scalar( @{ $links } ) )
            {

                foreach my $link ( @{ $links } )
                {

                    $sth = $sqlite3_dbh->prepare(
                        <<EOF
                        INSERT INTO facebook_page_links (facebook_pages_id, url)
                            SELECT facebook_pages_id, ?
                            FROM facebook_pages
                            WHERE page_url = ?
                              AND NOT EXISTS (
                                -- Unless it exists already for the same Facebook page
                                SELECT 1
                                FROM facebook_page_links
                                    INNER JOIN facebook_pages
                                        ON facebook_page_links.facebook_pages_id = facebook_pages.facebook_pages_id
                                WHERE facebook_page_links.url = ?
                                  AND facebook_pages.page_url = ?
                              )
EOF
                    );
                    $sth->bind_param( 1, $link );
                    $sth->bind_param( 2, $facebook_page_url );
                    $sth->bind_param( 3, $link );
                    $sth->bind_param( 4, $facebook_page_url );
                    unless ( $sth->execute() )
                    {
                        die "Adding link '$link' to Facebook page '$facebook_page_url' failed.";
                    }
                }
            }

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
Usage: $0 --pages_file facebook-pages.txt --output_database results.sqlite3
EOF

    my $pages_file;
    my $output_database;
    Getopt::Long::GetOptions(
        "pages_file=s"      => \$pages_file,
        "output_database=s" => \$output_database,
    ) or die $usage;
    die $usage unless ( $pages_file and $output_database );

    my @page_urls = split( /\r?\n/, read_file( $pages_file ) );

    say STDERR "Initializing output database '$output_database'...";
    my $sqlite3_dbh = DBI->connect( "dbi:SQLite:dbname=$output_database", "", "" );
    $sqlite3_dbh->do( 'PRAGMA foreign_keys = ON' );
    $sqlite3_dbh->do(
        <<EOF
        CREATE TABLE IF NOT EXISTS facebook_pages (
            facebook_pages_id INTEGER NOT NULL PRIMARY KEY,
            page_url TEXT NOT NULL
        )
EOF
    );
    $sqlite3_dbh->do(
        <<EOF
        CREATE UNIQUE INDEX IF NOT EXISTS facebook_pages_page_url_idx
        ON facebook_pages (page_url)
EOF
    );
    $sqlite3_dbh->do(
        <<EOF
        CREATE TABLE IF NOT EXISTS facebook_page_links (
            facebook_page_links_id INTEGER NOT NULL PRIMARY KEY,
            facebook_pages_id INTEGER NOT NULL,
            url TEXT NOT NULL,
            FOREIGN KEY (facebook_pages_id) REFERENCES facebook_pages (facebook_pages_id)
        )
EOF
    );
    $sqlite3_dbh->do(
        <<EOF
        CREATE INDEX IF NOT EXISTS facebook_page_links_facebook_pages_id_idx
        ON facebook_page_links (facebook_pages_id)
EOF
    );
    $sqlite3_dbh->do(
        <<EOF
        CREATE UNIQUE INDEX IF NOT EXISTS facebook_page_links_facebook_pages_id_url_idx
        ON facebook_page_links (facebook_pages_id, url)
EOF
    );

    foreach my $page_url ( @page_urls )
    {
        if ( $page_url )
        {
            fetch_facebook_page_links( $page_url, $sqlite3_dbh );
        }
    }
}

main();
