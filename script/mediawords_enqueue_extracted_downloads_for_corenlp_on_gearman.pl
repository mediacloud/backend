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
use MediaWords::GearmanFunction::AnnotateWithCoreNLP;

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    say STDERR "Fetching a list of extracted, unannotated downloads...";
    my $downloads = $db->query(
        <<EOF

        SELECT downloads_id
        FROM downloads
        WHERE extracted = 't'
          AND type = 'content'
          AND state = 'success'
          AND NOT EXISTS (
            SELECT *
            FROM corenlp_annotated_stories
            WHERE downloads.stories_id = corenlp_annotated_stories.stories_id
          )
        ORDER BY downloads_id ASC

EOF
    )->hashes;

    for my $download ( @{ $downloads } )
    {

        say STDERR 'Enqueueing download ID ' . $download->{ downloads_id } . ' for CoreNLP annotation...';
        MediaWords::GearmanFunction::AnnotateWithCoreNLP->enqueue_on_gearman( $download );

    }
}

main();
