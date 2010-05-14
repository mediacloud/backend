#!/usr/bin/perl

# various cleanup functions

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Time::Local;

use DBIx::Simple::MediaWords;
use MediaWords::DB;

# return date in YYY-MM-DD format
sub _get_ymd
{
    my ( $epoch ) = @_;

    my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime( $epoch );

    return sprintf( '%04d-%02d-%02d', $year + 1900, $mon + 1, $mday );
}

# merge stories with the same title from the media source on the same day
sub main
{

    my $db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info );

    eval { $db->query( "create table duplicate_stories (stories_id int, feeds_id int)" ); };
    $db->query( "truncate table duplicate_stories" );

    # iterate through each day, aggregating all stories from the same media source with the same title on the same day.
    for ( my $date = timelocal( 0, 0, 0, 1, 3, 107 ) ; $date < time ; $date += 86400 )
    {

        my $date_ymd = _get_ymd( $date );

        my $story_groups = $db->query(
            "select count(*) as num_stories, max(stories_id) as max_stories_id, title, media_id " . "  from stories " .
              "  where publish_date >= date '$date_ymd' " . "    and publish_date < date '$date_ymd' + interval '1 day' " .
              "  group by title, media_id having count(*) > 1" )->hashes;

        my $count = 0;
        for my $story_group ( @{ $story_groups } )
        {
            print STDERR "[$date_ymd] story: " . $count++ . " $story_group->{max_stories_id} $story_group->{num_stories}\n";

            $db->query(
                "insert into duplicate_stories (stories_id, feeds_id) " .
                  "  select s.stories_id, fsm.feeds_id from stories s " .
                  "      left join feeds_stories_map fsm on s.stories_id = fsm.stories_id " .
                  "    where s.title = ? and s.media_id = ? and " .
                  "      s.publish_date >= date '$date_ymd' and s.publish_date < date '$date_ymd' + interval '1 day'",
                $story_group->{ title },
                $story_group->{ media_id }
            );

            $db->query( "delete from feeds_stories_map where stories_id in (select stories_id from duplicate_stories)" );

            $db->query(
                "insert into feeds_stories_map (stories_id, feeds_id) " .
                  "  select distinct ?::int, feeds_id from duplicate_stories where feeds_id is not null",
                $story_group->{ max_stories_id }
            );

            $db->query(
                "delete from stories where stories_id in (" .
                  "  select stories_id from duplicate_stories where stories_id <> ?)",
                $story_group->{ max_stories_id }
            );

        }
    }

    $db->query( "drop table duplicate_stories" );
}

main();
