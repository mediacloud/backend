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

    my $snapshot = $db->query( <<SQL,
        INSERT INTO snapshots (
            topics_id,
            start_date,
            end_date,
            snapshot_date,
            note,
            bot_policy,
            seed_queries
        ) VALUES ( ?, ?, ?, now(), ?, ?, ? )
        RETURNING *
SQL
        $topics_id, $start_date, $end_date, $note, $bot_policy, $sq_json
    )->hash();

    $snapshot->{ topic } = $topic;

    return $snapshot;
}

# for each story in the list, get the list of foci for the timespan snapshot
sub get_story_foci($$$)
{
    my ( $db, $timespan, $stories ) = @_;

    # enumerate the stories ids to get a decent query plan
    my $stories_ids_list = join( ',', map { $_->{ stories_id } } @{ $stories } ) || '-1';

    my $foci = $db->query( <<SQL,
        SELECT
            slc.stories_id,
            f.foci_id,
            f.name,
            fs.name AS focal_set_name
        FROM snap.story_link_counts AS slc
            INNER JOIN timespans AS a ON
                a.topics_id = slc.topics_id AND
                a.timespans_id = slc.timespans_id
            INNER JOIN timespans AS b ON
                a.topics_id = b.topics_id AND
                a.snapshots_id = b.snapshots_id AND
                a.start_date = b.start_date AND
                a.end_date = b.end_date AND
                a.period = b.period
            INNER JOIN foci AS f ON
                f.topics_id = b.topics_id AND
                f.foci_id = b.foci_id
            INNER JOIN focal_sets AS fs ON
                f.topics_id = fs.topics_id AND
                f.focal_sets_id = fs.focal_sets_id
            INNER JOIN snap.story_link_counts AS slcb ON
                slcb.topics_id = slc.topics_id AND
                slcb.stories_id = slc.stories_id AND
                slcb.topics_id = b.topics_id AND
                slcb.timespans_id = b.timespans_id
        WHERE
            slc.stories_id IN ($stories_ids_list) AND
            slc.topics_id = \$1 AND
            a.timespans_id = \$2
SQL
        $timespan->{ topics_id }, $timespan->{ timespans_id }
    )->hashes;

    return $foci;
}

# for each story in the list, get the list of url sharing counts for the timespan snapshot
sub get_story_counts($$$)
{
    my ( $db, $timespan, $stories ) = @_;

    my $stories_ids_list = join( ',', map { int( $_->{ stories_id } // 0 ) } @{ $stories } ) || -1;

    my $counts = $db->query( <<SQL,
        SELECT
            b.stories_id,
            b.post_count,
            b.author_count,
            b.channel_count,
            f.name AS focus_name,
            (f.arguments->>'topic_seed_queries_id')::BIGINT AS topic_seed_queries_id
        FROM snap.story_link_counts AS a
            INNER JOIN timespans AS at ON
                a.topics_id = at.topics_id AND
                a.timespans_id = at.timespans_id
            INNER JOIN timespans AS bt ON
                at.topics_id = bt.topics_id AND
                at.snapshots_id = bt.snapshots_id AND
                at.period = bt.period AND
                at.start_date = bt.start_date
            INNER JOIN foci AS f ON
                bt.topics_id = f.topics_id AND
                bt.foci_id = f.foci_id
            INNER JOIN focal_sets AS fs ON
                fs.topics_id = f.topics_id AND
                fs.focal_sets_id = f.focal_sets_id AND
                fs.focal_technique = 'URL Sharing'
            INNER JOIN snap.story_link_counts AS b ON
                b.topics_id = bt.topics_id AND
                b.timespans_id = bt.timespans_id AND
                b.stories_id = a.stories_id
        WHERE
            b.stories_id IN ($stories_ids_list) AND
            a.topics_id = ? AND
            a.timespans_id = ?
SQL
        $timespan->{ topics_id }, $timespan->{ timespans_id }
    )->hashes;

    return $counts;
}

# for each medium in the list, get the list of url sharing counts for the timespan snapshot
sub get_medium_counts($$$)
{
    my ( $db, $timespan, $media ) = @_;

    my $media_ids_list = join( ',', map { int( $_->{ media_id } // 0 ) } @{ $media } ) || -1;

    my $counts = $db->query( <<SQL,
        SELECT
            b.media_id,
            b.sum_post_count,
            b.sum_author_count,
            b.sum_channel_count,
            f.name AS focus_name,
            (f.arguments->>'topic_seed_queries_id')::BIGINT topic_seed_queries_id
        FROM snap.medium_link_counts AS a
            INNER JOIN timespans AS at ON
                a.topics_id = at.topics_id AND
                a.timespans_id = at.timespans_id
            INNER JOIN timespans AS bt ON
                at.topics_id = bt.topics_id AND
                at.snapshots_id = bt.snapshots_id AND
                at.period = bt.period AND
                at.start_date = bt.start_date
            INNER JOIN foci AS f ON
                bt.topics_id = f.topics_id AND
                bt.foci_id = f.foci_id
            INNER JOIN focal_sets AS fs ON
                fs.topics_id = f.topics_id AND
                fs.focal_sets_id = f.focal_sets_id AND
                fs.focal_technique = 'URL Sharing'
            INNER JOIN snap.medium_link_counts AS b ON
                b.topics_id = bt.topics_id AND
                b.timespans_id = bt.timespans_id AND
                b.topics_id = a.topics_id AND
                b.media_id = a.media_id
        WHERE
            b.media_id IN ($media_ids_list) AND
            a.topics_id = ? AND
            a.timespans_id = ?
SQL
        $timespan->{ topics_id }, $timespan->{ timespans_id }
    )->hashes;

    return $counts;
}

1;
