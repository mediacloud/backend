#!/usr/bin/env perl

# generate media_stats rows for the days in the given date range.  if date range is specified,
# generate rows for every day starting with the last date in media stats up to yesterday

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;

use MediaWords::DB;
use MediaWords::Util::SQL;

# return a default start date of the earliest date later than the
# latest date in media_stats or else yesterday, if yesterday's
# date is not media_stats
sub _get_default_start_date
{
    my ( $db ) = @_;

    my $media_stat = $db->query( <<END )->hash;
select * from media_stats 
    where stat_date < now() - interval '1 day' 
    order by stat_date desc 
    limit 1
END

    my $date = MediaWords::Util::SQL::increment_day( $media_stat->{ stat_date } ) if ( $media_stat );

    $date ||= substr( MediaWords::Util::SQL::get_sql_date_from_epoch( time() - 86400 ), 0, 10 );

    my $media_stat_yesterday = $db->query( <<END, $date )->hash;
select * from media_stats where stat_date = ?
END

    return $date unless ( $media_stat_yesterday );

    die( "unable to find default start date -- date for yesterday already exists." );

}

# generate media stats for the given day
sub _generate_media_stats
{
    my ( $db, $date ) = @_;

    print STDERR "generating date: $date...\n";

    $db->query( "delete from media_stats where stat_date = ?", $date );

    $db->query( <<'END', $date );
insert into media_stats ( 
    num_stories, 
    num_sentences, 
    mean_num_sentences, 
    num_stories_with_sentences, 
    mean_text_length, 
    num_stories_with_text, 
    media_id, 
    stat_date )
    
with media_stats_stories as ( 
    select * from media_stats_stories_all where date_trunc( 'day', publish_date ) = $1::date
)
select 
        count(*) num_stories, 
        sum( coalesce( ss_ag.num_sentences, 0 ) ) num_sentences, 
        avg( coalesce( ss_ag.num_sentences, 0 ) )::int mean_num_sentences,
        sum( case when ss_ag.num_sentences > 0 then 1 else 0 end ) num_stories_with_sentences,
        avg( coalesce( dt_ag.text_length, 0 ) )::int mean_text_length,
        sum( case when dt_ag.text_length > 0 then 1 else 0 end ) num_stories_with_text,
        m.media_id,
        date_trunc( 'day', s.publish_date ) stat_date
        
    from media_stats_stories s
        join media m on ( s.media_id = m.media_id ) 
        
        left join 
            ( select ss.stories_id, count(*) num_sentences 
                from story_sentences ss 
                where date_trunc( 'day', publish_date ) = $1
                group by ss.stories_id ) ss_ag on ( s.stories_id = ss_ag.stories_id ) 

        left join 
            ( select mss.stories_id, sum( dt.download_text_length ) text_length
                from media_stats_stories mss
                    join download_texts dt on ( mss.downloads_id = dt.downloads_id )
                group by mss.stories_id ) dt_ag on ( s.stories_id = dt_ag.stories_id ) 

    group by m.media_id, date_trunc( 'day', publish_date ) 
    order by m.media_id;
END

    print STDERR "done\n";
}

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    my ( $start_date, $end_date );
    Getopt::Long::GetOptions(
        "start_date=s" => \$start_date,
        "end_date=s"   => \$end_date,
    ) || return;

    $start_date ||= _get_default_start_date( $db );
    $end_date ||= substr( MediaWords::Util::SQL::get_sql_date_from_epoch( time() - 86400 ), 0, 10 );

    print STDERR "generating media_stats_stories_all for $start_date - $end_date ...\n";
    $db->query( <<'END', $start_date, $end_date );
create temporary table media_stats_stories_all as 
    select s.media_id, s.publish_date, d.stories_id, d.downloads_id 
        from stories s 
            join downloads d on ( s.stories_id = d.stories_id ) 
        where date_trunc( 'day', publish_date ) between $1 and $2
END

    for ( my $date = $start_date ; $date le $end_date ; $date = MediaWords::Util::SQL::increment_day( $date ) )
    {
        _generate_media_stats( $db, $date );
    }
}

main();
