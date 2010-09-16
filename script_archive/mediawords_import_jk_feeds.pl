#!/usr/bin/perl

# import list of lines from morning analytics, with blog url and cluster num

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use HTTP::Request;
use LWP::UserAgent;
use Text::CSV_XS;
use Text::Trim;

use DBIx::Simple::MediaWords;
use Feed::Scrape;
use MediaWords::DB;

# add the given tag to the media source
sub add_tag
{
    my ( $db, $media_id, $tag_set_name, $tag_name ) = @_;
    
    my $tag_set = $db->find_or_create( 'tag_sets', { name => $tag_set_name } );
    my $tag = $db->find_or_create( 'tags', { tag => $tag_name, tag_sets_id => $tag_set->{ tag_sets_id } } );

    $db->find_or_create( 'media_tags_map', { media_id => $media_id, tags_id => $tag->{ tags_id } } );
}

# create a media source from a blog url and a 
sub create_medium
{
    my ( $blog_url, $cluster_num ) = @_;

    eval {        

        my $db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info );

        if ( $db->query( "select * from media where url = ?", $blog_url )->hash )
        {
            print STDERR "medium '$blog_url' already exists\n";
            return;
        }

        my $response = LWP::UserAgent->new->request( HTTP::Request->new( GET => $blog_url ) );

        if ( !$response->is_success )
        {
            print STDERR "Unable to fetch '$blog_url': " . $response->status_line . "\n";
            return;
        }

        my $html = $response->decoded_content;
        
        my $medium_name;
        if ( $html =~ /<title>(.*)<\/title>/i )
        {
            $medium_name = $1;
        }
        else {
            $medium_name = $blog_url;
        }

        my $feed_url;
        if ( $blog_url =~ /livejournal.com/ )
        {
            $feed_url = "$blog_url/data/atom";
        }
        elsif ($blog_url =~ /liveinternet.ru/ )
        {
            $feed_url = "$blog_url/rss";
        }
        
        if ( $db->query( "select * from media where name = ?", $medium_name )->hash )
        {
            print STDERR "medium '$medium_name' ($blog_url) already exists\n";
            return;
        }

        my $medium;
        if ( $feed_url )
        {
            $medium = $db->create
                ( 'media', { name => $medium_name, url => $blog_url, moderated => 'true', feeds_added => 'true' } );
            $db->create( 'feeds', { name => $medium_name, url => $feed_url, media_id => $medium->{ media_id } } );
        }
        else {
            $medium = $db->create
                ( 'media', { name => $medium_name, url => $blog_url, moderated => 'false', feeds_added => 'false' } );
        }

        add_tag( $db, $medium->{ media_id }, 'collection', 'morning_analytics_russia_20100915' );
        add_tag( $db, $medium->{ media_id }, 'morning_analytics_russia_20100915_cluster', $cluster_num );

        print STDERR "added $blog_url, $medium_name, $feed_url\n";
    };
    if ( $@ )
    {
        print STDERR "Error adding $blog_url: $@\n";
    }
    return 1;
}

sub main
{
    my ( $file ) = @ARGV;

    binmode STDIN, ":utf8";
    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    if ( !$file )
    {
        die( "usage: mediawords_import_jk_blogs.pl <csv file>\n" );
    }

    my $csv = Text::CSV_XS->new( { binary => 1 } ) || die "Cannot use CSV: " . Text::CSV_XS->error_diag();

    open my $fh, "<:encoding(utf8)", $file || die "Unable to open file $file: $!\n";

    $csv->column_names( $csv->getline( $fh ) );

    my $media_added = 0;
    while ( my $row = $csv->getline_hr( $fh ) )
    {
        if ( create_medium( $row->{ url }, $row->{ cluster } ) )
        {
            print STDERR "BLOGS ADDED: " . ++$media_added . "\n";
        }
    }
}

main();

