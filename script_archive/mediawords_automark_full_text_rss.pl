#!/usr/bin/perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Encode;
use MediaWords::DB;
use DBIx::Simple::MediaWords;
use MediaWords::Tagger;
use MediaWords::DBI::Downloads;
use List::Uniq ':all';
use Perl6::Say;

sub main
{

    my $dbs = MediaWords::DB::connect_to_db;

    my @media_ids_to_update = $dbs->query('select media.media_id from media_rss_full_text_detection_data natural join media where  avg_similarity >= 0.97 and avg_rss_length > 1000 and full_text_rss is null')->flat;

    say "updating " . scalar(@media_ids_to_update) . " media ids";

    return if scalar(@media_ids_to_update) == 0;

    $dbs->query(
'update media set full_text_rss = true where media_id in (??)',
		@media_ids_to_update) || die;

    $dbs->commit;
}

main();
