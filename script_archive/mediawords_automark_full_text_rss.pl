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

    my @media_ids_to_update = $dbs->query(
'select media.media_id from media_rss_full_text_detection_data natural join media where  avg_similarity >= 0.97 and avg_rss_length > 1000 and full_text_rss is null'
    )->flat;

    say "updating " . scalar( @media_ids_to_update ) . " media ids";

    return if scalar( @media_ids_to_update ) == 0;

    $dbs->query( 'update media set full_text_rss = true where media_id in (??)', @media_ids_to_update ) || die;

    @media_ids_to_update = $dbs->query(
'select media_id from (select media_id, avg_rss_length, avg_extracted_length, (abs(avg_rss_length-avg_extracted_length)/avg_rss_length) as length_proportion  from media_rss_full_text_detection_data where avg_rss_length > 400 ) as foo where length_proportion < 0.03'
    )->flat;

    $dbs->query(
"update media set full_text_rss = true where full_text_rss is null and url like '%livejournal%' and media_id in (??)",
        @media_ids_to_update
    );

}

main();
