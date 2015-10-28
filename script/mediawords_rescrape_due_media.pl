#!/usr/bin/env perl
#
# Rescape media which hasn't been rescraped in a while
#
# Usage: $0 [ --tag tag_name ]
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
use MediaWords::GearmanFunction;
use MediaWords::GearmanFunction::RescrapeMedia;

use Readonly;
use Getopt::Long;

sub main
{
    unless ( MediaWords::GearmanFunction::gearman_is_enabled() )
    {
        die "Gearman is disabled.";
    }

    Readonly my $usage => <<EOF;
Usage: $0 [ --tag tag_name ]
EOF

    my ( $tag );

    Getopt::Long::GetOptions( 'tag=s' => \$tag, ) or die $usage;

    my $db = MediaWords::DB::connect_to_db;

    my $tag_condition = '';
    if ( $tag )
    {
        $tag_condition = <<EOF;
    AND EXISTS (
        SELECT 1
        FROM media_tags_map
            INNER JOIN tags ON media_tags_map.tags_id = tags.tags_id
        WHERE media_tags_map.media_id = media_rescraping.media_id
          AND tags.tag = '$tag'
    )
EOF
    }

    my $due_media = $db->query(
        <<"EOF"
        SELECT media_id
        FROM media_rescraping
        WHERE disable = 'f'
          AND (last_rescrape_time IS NULL OR last_rescrape_time < NOW() - INTERVAL '1 year - 2 days')
          $tag_condition

          -- skip spidered media
        AND NOT (

            -- does not have "spidered:spidered" tag
            EXISTS (
                SELECT 1
                FROM tags AS tags
                    INNER JOIN media_tags_map
                        ON tags.tags_id = media_tags_map.tags_id
                    INNER JOIN tag_sets
                        ON tags.tag_sets_id = tag_sets.tag_sets_id
                WHERE media_tags_map.media_id = media_rescraping.media_id
                  AND tag_sets.name = 'spidered'
                  AND tags.tag = 'spidered'
            )

            -- does not have any active feeds
            AND NOT EXISTS (
                SELECT 1
                FROM feeds
                WHERE feeds.media_id = media_rescraping.media_id
                AND feed_status = 'active'
            )
        )

        ORDER BY media_id
EOF
    )->hashes;

    say STDERR 'Will rescrape media: ' . ( $tag ? 'with tag "' . $tag . '"' : 'all' );
    say STDERR "Media count to be rescraped: " . scalar( @{ $due_media } );
    foreach my $media ( @{ $due_media } )
    {
        MediaWords::GearmanFunction::RescrapeMedia->enqueue_on_gearman( { media_id => $media->{ media_id } } );
    }
}

main();
