package MediaWords::DBI::Feeds;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;

# delete a feed, making sure to delete any stories belonging to that feed that are
# not associate with another feed
sub delete_feed_and_stories
{
    my ( $db, $feeds_id ) = @_;

    $db->query( <<END, $feeds_id );
delete from stories s using feeds_stories_map fsm
    where s.stories_id = fsm.stories_id and fsm.feeds_id = ?
        and not exists 
            ( select 1 from feeds_stories_map fsm_b 
                  where fsm_b.stories_id = s.stories_id and fsm_b.feeds_id <> fsm.feeds_id )
END

    $db->query( <<END, $feeds_id );
delete from downloads d
    where d.feeds_id = ? and not exists ( select 1 from stories s where s.stories_id = d.stories_id )
END

    $db->query( <<END, $feeds_id );
update downloads d set feeds_id = fsm.feeds_id 
    from feeds_stories_map fsm 
    where d.feeds_id = ? and d.stories_id = fsm.stories_id  and fsm.feeds_id <> d.feeds_id 
END

    $db->query( "delete from downloads where stories_id is null and feeds_id = ?", $feeds_id );

    $db->query( "delete from feeds where feeds_id = ?", $feeds_id );
}

# (Temporarily) disable feed
sub disable_feed($$)
{
    my ( $db, $feeds_id ) = @_;

    $db->query(
        <<EOF,
        UPDATE feeds
        SET feed_status = 'inactive'
        WHERE feeds_id = ?
EOF
        $feeds_id
    );
}

1;
