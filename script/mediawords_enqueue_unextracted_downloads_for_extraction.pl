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

use Modern::Perl "2015";
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

    my $i = 0;
    for my $download ( @{ $downloads } )
    {

        say STDERR 'Enqueueing download ID ' . $download->{ downloads_id } . '...';
        MediaWords::GearmanFunction::ExtractAndVector->enqueue_on_gearman( { downloads_id => $download->{ downloads_id } } );

        # throttle to 100 connections a second to prevent running the
        # system out of connections stuck in TIME_WAIT
        sleep 1 if ( !( ++$i % 100 ) );
    }
}

main();
