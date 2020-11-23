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

# for each story in the list, get the list of foci for the timespan snapshot
sub get_story_foci($$$)
{
    my ( $db, $timespan, $stories ) = @_;

    # enumerate the stories ids to get a decent query plan
    my $stories_ids_list = join( ',', map { $_->{ stories_id } } @{ $stories } ) || '-1';

    my $foci = $db->query( <<SQL, $timespan->{ timespans_id } )->hashes;
select
        slc.stories_id,
        f.foci_id,
        f.name,
        fs.name focal_set_name
    from snap.story_link_counts slc
        join timespans a on ( a.timespans_id = slc.timespans_id )
        join timespans b on
            ( a.snapshots_id = b.snapshots_id and
                a.start_date = b.start_date and
                a.end_date = b.end_date and
                a.period = b.period )
        join foci f on ( f.foci_id = b.foci_id )
        join focal_sets fs on ( f.focal_sets_id = fs.focal_sets_id )
        join snap.story_link_counts slcb on
            ( slcb.stories_id = slc.stories_id and
                slcb.timespans_id = b.timespans_id )
    where
        slc.stories_id in ( $stories_ids_list ) and
        a.timespans_id = \$1
SQL

    return $foci;
}

# for each story in the list, get the list of url sharing counts for the timespan snapshot
sub get_story_counts($$$)
{
    my ( $db, $timespan, $stories ) = @_;

    my $stories_ids_list = join( ',', map { int( $_->{ stories_id } // 0 ) } @{ $stories } ) || -1;

    my $counts = $db->query( <<SQL, $timespan->{ timespans_id } )->hashes;
select
        b.stories_id, b.post_count, b.author_count, b.channel_count,
        f.name focus_name, (f.arguments->>'topic_seed_queries_id')::int topic_seed_queries_id
    from snap.story_link_counts a
        join timespans at using ( timespans_id )
        join timespans bt on
            ( at.snapshots_id = bt.snapshots_id and
                at.period = bt.period and
                at.start_date = bt.start_date )
        join foci f on ( bt.foci_id = f.foci_id )
        join focal_sets fs on ( fs.focal_sets_id = f.focal_sets_id and fs.focal_technique = 'URL Sharing' )
        join snap.story_link_counts b on ( b.timespans_id = bt.timespans_id and b.stories_id = a.stories_id )
    where  
        b.stories_id in ( $stories_ids_list ) and
        a.timespans_id = ?
SQL

    return $counts;
}

# for each medium in the list, get the list of url sharing counts for the timespan snapshot
sub get_medium_counts($$$)
{
    my ( $db, $timespan, $media ) = @_;

    my $media_ids_list = join( ',', map { int( $_->{ media_id } // 0 ) } @{ $media } ) || -1;

    my $counts = $db->query( <<SQL, $timespan->{ timespans_id } )->hashes;
select
        b.media_id, b.sum_post_count, b.sum_author_count, b.sum_channel_count,
        f.name focus_name, (f.arguments->>'topic_seed_queries_id')::int topic_seed_queries_id
    from snap.medium_link_counts a
        join timespans at using ( timespans_id )
        join timespans bt on
            ( at.snapshots_id = bt.snapshots_id and
                at.period = bt.period and
                at.start_date = bt.start_date )
        join foci f on ( bt.foci_id = f.foci_id )
        join focal_sets fs on ( fs.focal_sets_id = f.focal_sets_id and fs.focal_technique = 'URL Sharing' )
        join snap.medium_link_counts b on ( b.timespans_id = bt.timespans_id and b.media_id = a.media_id )
    where  
        b.media_id in ( $media_ids_list ) and 
        a.timespans_id = ?
SQL

    return $counts;
}

1;
