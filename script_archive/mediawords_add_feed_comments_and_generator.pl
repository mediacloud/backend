#!/usr/bin/perl

# set comments_anchor and generator for all existing feeds based on last feed download for each feed

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use XML::Entities;

use DBIx::Simple::MediaWords;
use MediaWords::DB;
use MediaWords::DBI::Downloads;
use MediaWords::DBI::Feeds;

sub main
{

    my $db = MediaWords::DB::connect_to_db();

# my $feeds = $db->query("select * from feeds where feeds_id in (select max(feeds_id) from feeds group by media_id) order by feeds_id")->hashes;
    my $feeds = $db->query( "select * from feeds order by feeds_id" )->hashes;

    for my $feed ( @{ $feeds } )
    {

        print( "feed: " . $feed->{ feeds_id } . "\t\t[" . $feed->{ url } . "]\n" );

        my $download = $db->query(
            "select * from downloads where stories_id in " .
              "  (select max(stories_id) from feeds_stories_map where feeds_id = ?) limit 1",
            $feed->{ feeds_id }
        )->hash;
        while ( $download->{ parent } )
        {
            $download = $db->query( "select * from downloads where downloads_id = ?", $download->{ parent } )->hash;
        }

        if ( $download->{ type } ne 'feed' )
        {
            warn( "root download is not a feed: $download->{downloads_id}" );
        }

        my $xml = MediaWords::DBI::Downloads::fetch_content( $download );

        #print "xml:\n******\n\n$$xml\n\n*******\n";

        my $generator        = MediaWords::DBI::Feeds::get_generator_from_xml( $$xml );
        my $comments_archive = MediaWords::DBI::Feeds::get_comments_archive_from_xml( $$xml );

        print( "\tgenerator: " .       ( $generator       || '' ) . "\n" );
        print( "\tcomments_anchor: " . ( $comments_anchor || '' ) . "\n" );

        if ( $generator || $comments_anchor )
        {
            $db->query( "update feeds set generator = ?, comments_anchor = ? where feeds_id = ?",
                $generator, $comments_anchor, $feed->{ feeds_id } );
        }
    }
}

main();
