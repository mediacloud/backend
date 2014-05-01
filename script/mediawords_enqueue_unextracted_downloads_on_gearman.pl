#!/usr/bin/env perl
#
# Enqueue unextracted downloads on Gearman.
#
# It is safe to run this as many times as you want because the extraction job
# on Gearman is unique so download extractions won't be duplicated.
#
# Usage: mediawords_enqueue_unextracted_downloads_on_gearman.pl
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

use MediaWords::DB;
use MediaWords::GearmanFunction::ExtractAndVector;

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    say STDERR "Fetching a list of unextracted downloads...";
    my $downloads = $db->query(
        <<EOF

        SELECT downloads_id
        FROM downloads
        WHERE extracted = 'f'
          AND type = 'content'
          AND state = 'success'
        ORDER BY stories_id ASC

EOF
    )->hashes;

    for my $download ( @{ $downloads } )
    {

        say STDERR 'Enqueueing download ID ' . $download->{ downloads_id } . '...';
        MediaWords::GearmanFunction::ExtractAndVector->enqueue_on_gearman( $download );

    }
}

main();
