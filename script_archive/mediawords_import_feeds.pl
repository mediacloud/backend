#!/usr/bin/perl

# import list of feeds one per line as media sources.  pass name of collection:* tag as the only argument.

# these get added to the moderation queue

# eg: mediawords_import_feeds.pl 'Top 10 Russian Mainstream Media' < ap-russian.txt

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use HTTP::Request;
use LWP::UserAgent;
use Text::Trim;

use DBIx::Simple::MediaWords;
use Feed::Scrape;
use MediaWords::DB;

# create a media source from a feed url
sub create_media
{
    my ( $feed_url ) = @_;
    
    eval {
        
        my $db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info );
    
        my $response = LWP::UserAgent->new->request( HTTP::Request->new( GET => $feed_url ) );

        if ( ! $response->is_success ) 
        {
            print STDERR "Unable to fetch '$feed_url': " . $response->status_line . "\n";
            return;
        }
    
        my $feed = Feed::Scrape->parse_feed( $response->decoded_content );
    
        my ( $medium_url, $medium_name );
        if ( $feed )
        {
            $medium_url = $feed->link;
            $medium_name = $feed->title;
        } 
        else {
            print STDERR "Unable to parse feed '$feed_url'\n";
        }

        $medium_url ||= $feed_url;
        $medium_name ||= $feed_url;
    
        if ( $db->query( "select * from media where name = ?", $medium_name )->hash )
        {
            print STDERR "medium '$medium_name' already exists\n";
            return;
        }
    
        my $medium = $db->create( 'media', { name => $medium_name, url => $medium_url, moderated => 'true', feeds_added => 'true' } );
    
        $db->create( 'feeds', { name => $medium_name, url => $feed_url, media_id => $medium->{ media_id } } );
    
        my $tag_set = $db->find_or_create( 'tag_sets', { name => 'collection' } );

        my $tag = $db->find_or_create( 'tags', { tag => $collection_tag, tag_sets_id => $tag_set->{ tag_sets_id } } );
    
        $db->find_or_create( 'media_tags_map', { media_id => $medium->{ media_id }, tags_id => $tag->{ tags_id } } );
    
        print STDERR "added $medium_name, $medium_url, $feed_url\n";
    };
    if ( $@ )
    {
        print STDERR "Error adding $feed_url: $@\n";
    }
}

sub main
{
    my ( $collection_tag ) = @ARGV;
    
    if ( !$collection_tag )
    {
        die( "usage: mediawords_import_feeds.pl <collection tag name>" );
    }
    
    while ( my $feed_url = <STDIN> )
    {
        chomp( $feed_url );
        
        create_media( $collection_tag, $feed_url );
    }
    
}

main();  
    
