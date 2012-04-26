package MediaWords::Pg::Cleanup;

# various cleanup functions

use strict;

use Time::Local;

use MediaWords::Pg;

# return date in YYY-MM-DD format
sub _get_ymd
{
    my ( $epoch ) = @_;

    my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime( $epoch );

    return sprintf( '%04d-%02d-%02d', $year + 1900, $mon + 1, $mday );
}

# merge stories with the same title from the media source on the same day
sub remove_duplicate_stories
{
    my ( $month, $year ) = @_;

    exec_query( "create temporary table duplicate_stories (stories_id int, feeds_id int) on commit drop" );

    my $date = timelocal( 0, 0, 0, 1, $month - 1, $year - 1900 );

    # iterate through each day, aggregating all stories from the same media source with the same title on the same day.
    for ( my $date = timelocal( 0, 0, 0, 1, $month - 1, $year - 1900 ) ; $date < time ; $date += 86400 )
    {

        if ( $month != ( localtime( $date ) )[ 4 ] + 1 )
        {
            last;
        }
        my $date_ymd = _get_ymd( $date );

        my $sth =
          query( "select count(*) as num_stories, max(stories_id) as max_stories_id, title, media_id from stories " .
              "where publish_date >= date '$date_ymd' and publish_date < date '$date_ymd' + interval '1 day' " .
              "group by title, media_id having count(*) > 1" );
        my $count = 0;
        while ( my $story_group = fetchrow( $sth ) )
        {
            pg_log( "[$date_ymd] story: " . $count++ . " " . $story_group->{ max_stories_id } . " " .
                  $story_group->{ num_stories } );

            exec_prepared(
                "insert into duplicate_stories (stories_id, feeds_id) " .
                  "  select fsm.stories_id, fsm.feeds_id from feeds_stories_map fsm, stories s " .
                  "    where s.title = \$1 and s.media_id = \$2 and " .
                  "      s.publish_date >= date '$date_ymd' and s.publish_date < date '$date_ymd' + interval '1 day' and " .
                  "      s.stories_id = fsm.stories_id",
                [ qw( TEXT INT ) ],
                [ $story_group->{ title }, $story_group->{ media_id } ]
            );

            exec_prepared( "delete from feeds_stories_map where stories_id in (select stories_id from duplicate_stories)" );

            exec_prepared(
                "insert into feeds_stories_map (stories_id, feeds_id) select distinct \$1, feeds_id from duplicate_stories",
                [ qw( INT ) ],
                [ $story_group->{ max_stories_id } ]
            );

            exec_prepared(
                "delete from stories where stories_id in (" .
                  "  select stories_id from duplicate_stories where stories_id <> \$1)",
                [ qw( INT ) ],
                [ $story_group->{ max_stories_id } ]
            );

            exec_prepared( "truncate table duplicate_stories" );
        }

        #exec_query("drop table duplicate_stories");

    }
}

1;
