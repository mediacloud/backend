package MediaWords::DBI::Media::Rescrape;

#
# Media (re)scraping utilities
#

use strict;
use warnings;

use Modern::Perl "2013";

use MediaWords::CommonLibs;

use MediaWords::DBI::Media;
use MediaWords::GearmanFunction::RescrapeMedia;
use Feed::Scrape::MediaWords;

# add default feeds for a single medium
sub enqueue_rescrape_media($)
{
    my ( $medium ) = @_;

    return MediaWords::GearmanFunction::RescrapeMedia->enqueue_on_gearman( { media_id => $medium->{ media_id } } );
}

# for each medium in $media, enqueue an RescrapeMedia job for any medium
# that is lacking feeds
sub add_feeds_for_feedless_media
{
    my ( $db, $media ) = @_;

    for my $medium ( @{ $media } )
    {
        my $media_has_active_syndicated_feeds = $db->query(
            <<END,
            SELECT 1
            FROM media
            WHERE media_id = ?
              AND media_has_active_syndicated_feeds(media_id) = 't'
END
            $medium->{ media_id }
        )->hash;

        unless ( $media_has_active_syndicated_feeds )
        {
            enqueue_rescrape_media( $medium );
        }
    }
}

# (re-)enqueue RescrapeMedia jobs for all unmoderated media
# ("RescrapeMedia" Gearman function is "unique", so Gearman will skip media
# IDs that are already enqueued)
sub enqueue_rescrape_media_for_unmoderated_media($)
{
    my ( $db ) = @_;

    my $media = $db->query(
        <<EOF
        SELECT *
        FROM media
        WHERE media_has_active_syndicated_feeds(media_id) = 'f'
EOF
    )->hashes;

    map { enqueue_rescrape_media( $_ ) } @{ $media };

    return 1;
}

# Search and add new feeds for unmoderated media (media sources that have not
# had default feeds added to them).
#
# Look for feeds that are most likely to be real feeds.  If we find more than
# one but no more than MAX_DEFAULT_FEEDS of those feeds, use the first such one
# and do not moderate the source.  Else, do a more expansive search and mark
# for moderation.
sub rescrape_media($$)
{
    my ( $db, $media_id ) = @_;

    my $medium = $db->find_by_id( 'media', $media_id );
    unless ( $medium )
    {
        die "Media ID $media_id does not exist.";
    }

    my ( $feed_links, $need_to_moderate, $existing_urls ) =
      Feed::Scrape::get_feed_links_and_need_to_moderate_and_existing_urls( $db, $medium );

    $db->begin_work;

    for my $feed_link ( @{ $feed_links } )
    {
        my $feed = {
            name        => $feed_link->{ name },
            url         => $feed_link->{ url },
            media_id    => $medium->{ media_id },
            feed_type   => $feed_link->{ feed_type } || 'syndicated',
            feed_status => $need_to_moderate ? 'inactive' : 'active',
        };

        my $existing_feed = $db->query( <<END, $feed_link->{ url }, $medium->{ media_id } )->hash;
select * from feeds where url = ? and media_id = ?
END
        if ( $existing_feed )
        {
            $db->update_by_id( 'feeds', $existing_feed->{ feeds_id }, $feed );
        }
        else
        {
            eval { $db->create( 'feeds', $feed ); };
        }

        if ( $@ )
        {
            my $error = "Error adding feed $feed_link->{ url }: $@\n";
            $medium->{ moderation_notes } .= $error;
            print $error;
            next;
        }
        else
        {
            say STDERR "ADDED $medium->{ name }: $feed->{ name } " .
              "[$feed->{ feed_type }, $feed->{ feed_status }]" . " - $feed->{ url }\n";
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
        "UPDATE media SET moderation_notes = ?, moderated = ? WHERE media_id = ?",
        $medium->{ moderation_notes },
        $moderated, $medium->{ media_id }
    );

    $db->commit;
}

1;
