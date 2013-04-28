#!/usr/bin/env perl

# periodically check for new media sources that have not had default feeds added to them and add the default feeds.
# look for feeds that are most likely to be real feeds.  If we find more than one but no more than MAX_DEFAULT_FEEDS
# of those feeds, use the first such one and do not moderate the source.  Else, do a more expansive search
# and mark for moderation.

use strict;
use warnings;

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
            my ( $feed_links, $need_to_moderate, $existing_urls ) =
              Feed::Scrape::get_feed_links_and_need_to_moderate_and_existing_urls( $db, $medium );

            for my $feed_link ( @{ $feed_links } )
            {
                print "ADDED $medium->{ name }: [$feed_link->{ feed_type }] $feed_link->{ name } - $feed_link->{ url }\n";
                my $feed = {
                    name      => $feed_link->{ name },
                    url       => $feed_link->{ url },
                    media_id  => $medium->{ media_id },
                    feed_type => $feed_link->{ feed_type } || 'syndicated'
                };
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

            my $moderated = $need_to_moderate ? 'f' : 't';

            $db->query(
                "update media set feeds_added = true, moderation_notes = ?, moderated = ? where media_id = ?",
                $medium->{ moderation_notes },
                $moderated, $medium->{ media_id }
            );

        }

        $db->disconnect;

        sleep( 60 );
    }
}

main();
