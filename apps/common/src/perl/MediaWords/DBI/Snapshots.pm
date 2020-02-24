package MediaWords::DBI::Snapshots;

#
# Various functions related to snapshots
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::ParseJSON;

# create the snapshot row for the current snapshot
sub create_snapshot_row ($$;$$$$)
{
    my ( $db, $topic, $start_date, $end_date, $note, $bot_policy ) = @_;

    $start_date //= $topic->{ start_date };
    $end_date //= $topic->{ end_date };
    $note //= '';

    my $topics_id = $topic->{ topics_id };

    my $tsqs = $db->query( 'select * from topic_seed_queries where topics_id = ?', $topics_id )->hashes();

    my $topic_media_tags = $db->query( "select * from topics_media_tags_map where topics_id = ?", $topics_id )->hashes;
    my $topic_media = $db->query( "select * from topics_media_map where topics_id = ?", $topics_id )->hashes;

    my $seed_queries = {
        topic => $topic,
        topic_media => $topic_media,
        topic_media_tags => $topic_media_tags,
        topic_seed_queries => $tsqs
    };

    my $sq_json = MediaWords::Util::ParseJSON::encode_json( $seed_queries );

    my $snapshot = $db->query( <<END, $topics_id, $start_date, $end_date, $note, $bot_policy, $sq_json )->hash;
insert into snapshots
    ( topics_id, start_date, end_date, snapshot_date, note, bot_policy, seed_queries )
    values ( ?, ?, ?, now(), ?, ?, ? )
    returning *
END

    $snapshot->{ topic } = $topic;

    return $snapshot;
}

1;
