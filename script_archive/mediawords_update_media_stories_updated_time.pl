#!/usr/bin/env perl

# update db_row_last_updated for each story associated with media source in
# media_stories_updated_time_queue.  we do this through a daemon rather than
# through a trigger to avoid super long single queries

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    while ( 1 )
    {
        my ( $num_media ) = $db->query( "select count(*) from media_update_time_queue" )->flat;
        print STDERR "$num_media media in queue\n";

        if ( !$num_media )
        {
            sleep( 60 );
            next;
        }

        $db->begin;

        my $medium = $db->query( <<END )->hash;
select m.*, mu.* from media_update_time_queue mu natural join media m order by db_row_last_updated desc limit 1
END

        $db->query( <<END, $medium->{ media_id }, $medium->{ db_row_last_updated } );
create temporary table _sq  on commit drop as select stories_id from stories where media_id = ? and db_row_last_updated < ?
END

        my ( $num_stories ) = $db->query( "select count(*) from _sq" )->flat;

        print STDERR "updating $num_stories stories in $medium->{ name } [$medium->{ media_id }] ...\n";

        my $i = 0;
        for ( my $i = 0 ; $db->query( "select 1 from _sq limit 1" )->hash ; $i++ )
        {
            print STDERR ( $i * 1000 ) . " / $num_stories stories updated\n" if ( $i );
            $db->query( <<END, $medium->{ db_row_last_updated } );
update stories set db_row_last_updated = \$1
    where stories_id in ( select stories_id from _sq limit 1000 )
        and db_row_last_updated < \$1
END
            $db->query( <<END );
delete from _sq where stories_id in ( select stories_id from _sq limit 1000 )
END
        }

        $db->query( <<END, $medium->{ media_id }, $medium->{ db_row_last_updated } );
delete from media_update_time_queue where media_id = ? and db_row_last_updated <= ?
END

        $db->commit;
    }
}

main();
