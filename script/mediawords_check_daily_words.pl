#!/usr/bin/env perl

# run two checks to make sure the daily words table is getting written correctly:
# * check for any cases in the past month in which the total_daily_words entry for a
# collection media_set is less than 10% the value of the previous day.
# * check for any cases in the past month in which there is a total_daily_words
# for a collection media_set with a non-null dashboard_topics_id but none for a
# null dashboard_topics_id

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    binmode( STDOUT, 'utf8' );

    my $drop_days = $db->query(
"select ms.name, cur.publish_day cur_day, cur.total_count cur_count, prev.publish_day prev_day, prev.total_count prev_count "
          . "  from total_daily_words cur, total_daily_words prev, media_sets ms "
          . "  where cur.media_sets_id = ms.media_sets_id and cur.media_sets_id = prev.media_sets_id "
          . "    and cur.dashboard_topics_id is null and prev.dashboard_topics_id is null "
          . "    and cur.publish_day = prev.publish_day + interval '1 day' "
          . "    and prev.total_count > 0 and ( cur.total_count::float / prev.total_count::float ) < 0.1 "
          . "    and ms.set_type = 'collection' and cur.publish_day > now() - interval '1 month' "
          . "    and prev.total_count > 10000 "
          . "  order by cur.publish_day, ms.media_sets_id" )->hashes;

    for my $day ( @{ $drop_days } )
    {
        print
          "90% drop: $day->{ name } / $day->{ cur_day } / $day->{ cur_count } / $day->{ prev_day } / $day->{ prev_count }\n";
    }

    my $topic_days =
      $db->query( "select ms.name, publish_day from  total_daily_words tdw, media_sets ms " .
          "  where  ms.set_type = 'collection' and ms.media_sets_id = tdw.media_sets_id " .
          "    and not ( dashboard_topics_id is null ) and publish_day > now() - interval '1 month'" . "except " .
          "select ms.name, publish_day from  total_daily_words tdw, media_sets ms " .
          "  where tdw.media_sets_id = ms.media_sets_id and ms.set_type = 'collection' " .
          "    and ( dashboard_topics_id is null ) " . "  order by publish_day, name" )->hashes;

    for my $day ( @{ $topic_days } )
    {
        print "topic day: $day->{ name } / $day->{ publish_day }\n";
    }
}

main();
