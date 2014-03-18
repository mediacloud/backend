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

    say STDERR "Fetching a list of extracted, unannotated, English language downloads...";
    my $downloads = $db->query(
        <<EOF

        SELECT downloads_id
        FROM downloads AS d
            INNER JOIN stories AS s ON d.stories_id = s.stories_id
        WHERE d.extracted = 't'
          AND d.type = 'content'
          AND d.state = 'success'

          -- Stories with language field set to NULL are the ones fetched
          -- before introduction of the multilanguage support, so they are
          -- assumed to be in English
          AND (s.language = 'en' OR s.language IS NULL)

          AND NOT EXISTS (
            SELECT *
            FROM corenlp_annotated_stories
            WHERE d.stories_id = corenlp_annotated_stories.stories_id
          )
    
        ORDER BY d.downloads_id ASC

EOF
    )->hashes;

    for my $download ( @{ $downloads } )
    {

        say STDERR 'Enqueueing download ID ' . $download->{ downloads_id } . ' for CoreNLP annotation...';
        MediaWords::GearmanFunction::AnnotateWithCoreNLP->enqueue_on_gearman( $download );

    }
}

main();
