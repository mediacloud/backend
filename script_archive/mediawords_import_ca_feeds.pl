#!/usr/bin/env perl

# import list of ca initiative feeds from csv

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
use URI::Escape;

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

# create a twitter rss feed from a twitter url
# https://api.twitter.com/1/jennymedina/lists/california-political-news/statuses.atom
# https://search.twitter.com/search.atom?q=%23CAGov
sub get_twitter_feed
{
    my ( $url ) = @_;
    
    if ( $url =~ /twitter.com\/([^\/]+)$/ )
    {
        my $esc_name = URI::Escape::uri_escape( $1 );
        return "http://api.twitter.com/1/statuses/user_timeline.rss?screen_name=$esc_name";
    } 
    elsif ( $url =~ /twitter.com\/#!\/([^\/]+)\/([^\/]+)/ )
    {
        my $esc_user = URI::Escape::uri_escape( $1 );
        my $esc_list = URI::Escape::uri_escape( $2 );
        return "https://api.twitter.com/1/$esc_user/lists/$esc_list/statuses.atom";
    }
    else
    {
        warn( "Unable to parse twitter url: $url" );
        return $url;
    }
}

# create media source from the csv row hash
sub create_medium
{
    my ( $db, $source ) = @_;

    if ( $source->{ type } eq 'Twitter Hashtag' )
    {
        my $tag_name = substr( $source->{ name }, 1 );
        $source->{ rss } = "http://search.twitter.com/search.atom?q=%23$tag_name";
    }

    my $url = $source->{ url } || $source->{ rss } || $source->{ twitter } || $source->{ url };
    
    return unless ( $url );

    if ( my ( $media_id ) = $db->query( "select * from media where url = ?", $url )->flat )
    {
        print STDERR "medium '$url' already exists ( $media_id )\n";
        return $media_id;
    }

    if ( my ( $media_id ) = $db->query( "select media_id from media where name = ?", $source->{ name } )->flat )
    {
        print STDERR "medium '$source->{ name }' ( $url ) already exists\n";
        return $media_id;
    }

    my $feeds = [];
    push( @{ $feeds }, { type => 'syndicated', url => $source->{ rss } } ) if ( $source->{ rss } );
    push( @{ $feeds }, { type => 'syndicated', url => get_twitter_feed( $source->{ twitter } ) } ) if ( $source->{ twitter } );  
    push( @{ $feeds }, { type => 'web_page', url => $source->{ url } } ) if ( !@{ $feeds } && $source->{ url } );    
    push( @{ $feeds }, { type => 'web_page', url => $source->{ facebook } } ) if ( $source->{ facebook } );
        
    my $medium = $db->create( 'media', { name => $source->{ name }, url => $url, moderated => 'true', feeds_added => 'true' } );
    print STDERR "added medium: $medium->{ name } $medium->{ url }\n";

    for my $feed ( @{ $feeds } )
    {
        my $feed = $db->create( 'feeds', 
            { name => $source->{ name }, url => $feed->{ url }, feed_type => $feed->{ type }, media_id => $medium->{ media_id } } );
        print STDERR "\tfeed: $feed->{ name } $feed->{ type } $feed->{ url }\n";
    }

    return $medium->{ media_id };
}

sub main
{
    my ( $file ) = @ARGV;

    binmode STDIN,  ":utf8";
    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    die( "usage: $0 <csv file>\n" ) unless ( $file );

    my $csv = Text::CSV_XS->new( { binary => 1 } ) || die "Cannot use CSV: " . Text::CSV_XS->error_diag();

    open my $fh, "<:encoding(utf8)", $file || die "Unable to open file $file: $!\n";
    $csv->column_names( $csv->getline( $fh ) );

    my $media_added = 0;
    while ( my $row = $csv->getline_hr( $fh ) )
    {
        eval {
            my $db = MediaWords::DB::connect_to_db;

            if ( my $media_id = create_medium( $db, $row ) )
            {
                add_tag( $db, $media_id, 'collection', 'california_initiatives_20120911' );
                print STDERR "BLOGS ADDED: " . ++$media_added . "\n";
            }
        };
        if ( $@ )
        {
            print STDERR "Error adding $row->{ url }: $@\n";
        }
    }
}

main();

