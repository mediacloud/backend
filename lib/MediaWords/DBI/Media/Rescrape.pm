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

# for each medium in $media, enqueue an RescrapeMedia job for any medium
# that is lacking feeds
sub add_feeds_for_feedless_media
{
    my ( $db, $media ) = @_;

    for my $medium ( @{ $media } )
    {
        my $feeds = $db->query(
            <<END,
            SELECT *
            FROM feeds
            WHERE media_id = ?
              AND feed_status = 'active'
              AND feed_type = 'syndicated'
END
            $medium->{ media_id }
        )->hashes;

        MediaWords::DBI::Media::Rescrape::enqueue_rescrape_media( $medium ) unless ( @{ $feeds } );
    }
}

# add default feeds for a single medium
sub enqueue_rescrape_media($)
{
    my ( $medium ) = @_;

    return MediaWords::GearmanFunction::RescrapeMedia->enqueue_on_gearman( { media_id => $medium->{ media_id } } );
}

# (re-)enqueue RescrapeMedia jobs for all unmoderated media
# ("RescrapeMedia" Gearman function is "unique", so Gearman will skip media
# IDs that are already enqueued)
sub enqueue_rescrape_media_for_unmoderated_media($)
{
    my ( $db ) = @_;

    my $media = $db->query( "SELECT * FROM media WHERE media_has_feeds(media_id) = 'f'" )->hashes;

    map { enqueue_rescrape_media( $_ ) } @{ $media };

    return 1;
}

1;
