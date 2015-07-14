#!/usr/bin/env perl
#
# Rescape media which hasn't been rescraped in a while
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

sub main
{
    unless ( MediaWords::GearmanFunction::gearman_is_enabled() )
    {
        die "Gearman is disabled.";
    }

    my $db = MediaWords::DB::connect_to_db;

    my $due_media = $db->query(
        <<EOF
        SELECT media_id
        FROM media_rescraping
        WHERE disable = 'f'
          AND (last_rescrape_time IS NULL OR last_rescrape_time < NOW() - INTERVAL '3 months')
        ORDER BY media_id
EOF
    )->hashes;

    say STDERR "Media count to be rescraped: " . scalar( @{ $due_media } );
    foreach my $media ( @{ $due_media } )
    {
        MediaWords::GearmanFunction::RescrapeMedia->enqueue_on_gearman( { media_id => $media->{ media_id } } );
    }
}

main();
