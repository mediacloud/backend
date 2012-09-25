#!/usr/bin/env perl

# periodically check for new media sources that have not had default feeds added to them and add the default feeds

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use DBIx::Simple::MediaWords;
use Feed::Scrape::MediaWords;
use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

sub main
{
    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    while ( 1 )
    {
        my $db = MediaWords::DB::connect_to_db();

        my $media = $db->query( "select * from media where feeds_added = false order by media_id" )->hashes;

        for my $medium ( @{ $media } )
        {
            my $existing_urls = [];

            my $feed_links =
              Feed::Scrape::MediaWords->get_valid_feeds_from_single_index_url( $medium->{ url }, 1, $db, [],
                $existing_urls );

            for my $feed_link ( @{ $feed_links } )
            {
                print "ADDED $medium->{ name }: $feed_link->{ name } - $feed_link->{ url }\n";
                my $feed = { name => $feed_link->{ name }, url => $feed_link->{ url }, media_id => $medium->{ media_id } };
                eval { $db->create( 'feeds', $feed ); };

                if ( $@ )
                {
                    my $error = "Error adding feed $feed_link->{ url }: $@\n";
                    $medium->{ moderation_notes } .= $error;
                    print $error;
                    next;
                }
            }

            if ( @{ $existing_urls } )
            {
                my $error = "These urls were found but already exist in the database:\n" .
                  join( "\n", map { "\t$_" } @{ $existing_urls } ) . "\n";
                $medium->{ moderation_notes } .= $error;
                print $error;
            }

            $db->query(
                "update media set feeds_added = true, moderation_notes = ? where media_id = ?",
                $medium->{ moderation_notes },
                $medium->{ media_id }
            );
        }

        $db->disconnect;

        sleep( 60 );
    }
}

main();
