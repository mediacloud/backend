#!/usr/bin/perl

use strict;

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

sub main
{

    my $dbs = MediaWords::DB::connect_to_db;

    $dbs->query(
'update media set full_text_rss = true where media_id in (select media.media_id from media_rss_full_text_detection_data natural join media where  avg_similarity >= 0.97 and avg_rss_length > 1000 and full_text_rss is null)'
    ) || die;

    $dbs->commit;
}

