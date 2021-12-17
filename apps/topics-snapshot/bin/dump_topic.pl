#!/usr/bin/env perl

# dump the stories, story_links, media, and medium_links for a given topic timespan

use strict;
use warnings;

use MediaWords::CommonLibs;

use Data::Dumper;
use File::Slurp;

use MediaWords::TM::Dump;
use MediaWords::TM::Snapshot::ExtraFields;
use MediaWords::TM::Snapshot::Views;
use MediaWords::DB;

# Get an encoded csv snapshot of the story links for the given timespan.
sub _get_story_links_csv
{
    my ( $db, $timespan ) = @_;

    my $csv = MediaWords::TM::Dump::_get_query_as_csv( $db, <<SQL
        SELECT DISTINCT
            sl.source_stories_id AS source_stories_id,
            ss.title AS source_title,
            ss.url AS source_url,
            sm.name AS source_media_name,
            sm.url AS source_media_url,
            sm.media_id AS source_media_id,
            sl.ref_stories_id AS ref_stories_id,
            rs.title AS ref_title,
            rs.url AS ref_url,
            rm.name AS ref_media_name,
            rm.url AS ref_media_url,
            rm.media_id AS ref_media_id
        FROM
            snapshot_story_links AS sl,
            snap.live_stories AS ss,
            media AS sm,
            snap.live_stories AS rs,
            media AS rm
        WHERE
            sl.source_stories_id = ss.stories_id AND
            ss.media_id = sm.media_id AND
            sl.ref_stories_id = rs.stories_id AND
            rs.media_id = rm.media_id
SQL
    );

    return $csv;
}

# Get an encoded csv snapshot of the stories inr the given timespan.
sub _get_stories_csv
{
    my ( $db, $timespan ) = @_;

    my $res = $db->query( <<SQL
        SELECT
            s.stories_id,
            s.title,
            s.url,
            CASE
                WHEN (stm.tags_id IS NULL) THEN s.publish_date::TEXT
                ELSE 'undateable'
            END AS publish_date,
            m.name AS media_name,
            m.url AS media_url,
            m.media_id,
            slc.media_inlink_count,
            slc.inlink_count,
            slc.outlink_count,
            slc.facebook_share_count,
            slc.post_count
        FROM snapshot_stories AS s
            JOIN snapshot_media AS m ON
                s.media_id = m.media_id
            JOIN snapshot_story_link_counts AS slc ON
                s.stories_id = slc.stories_id
            LEFT JOIN (
                snapshot_stories_tags_map AS stm
                    JOIN tags AS t ON
                        stm.tags_id = t.tags_id AND
                        t.tag = 'undateable'
                    JOIN tag_sets AS ts ON
                        t.tag_sets_id = ts.tag_sets_id AND
                        ts.name = 'date_invalid'
            ) ON
                stm.stories_id = s.stories_id
        ORDER BY slc.media_inlink_count DESC
SQL
    );

    my $fields = $res->columns;

    my $stories = $res->hashes;

	my $story_post_counts = $db->query( <<SQL,
        WITH counts AS (
            SELECT
                COUNT(*) AS post_count,
                ts.stories_id,
                tsu.topic_seed_queries_id 
            FROM snapshot_stories AS ts 
                JOIN topic_seed_urls AS tsu USING (stories_id) 
                JOIN topic_post_days AS tpd USING (topic_seed_queries_id)
                JOIN timespans AS t USING (snapshots_id)
                JOIN snapshots AS s USING (snapshots_id)
            WHERE
                s.topics_id = tsu.topics_id AND
                t.timespans_id = ? AND
                (
                    period = 'overall' OR
                    tpd.day BETWEEN t.start_date AND t.end_date
                )
            GROUP BY
                stories_id,
                topic_seed_queries_id 
        ) 

        SELECT *
        FROM counts AS c 
            JOIN topic_seed_queries AS tsq USING (topic_seed_queries_id)
SQL
        $timespan->{ timespans_id }
    )->hashes;

    my $stories_lookup = {};
    map { $stories_lookup->{ $_->{ stories_id } } = $_ } @{ $stories };

    my $fields_lookup = {};

    for my $spc ( @{ $story_post_counts } )
    {
        my $story = $stories_lookup->{ $spc->{ stories_id } };
        my $label = "$spc->{ platform }_$spc->{ source }_$spc->{ topic_seed_queries_id }";
        $fields_lookup->{ $label } = 1;
        $story->{ $label } = $spc->{ post_count };
    }

    push( @{ $fields }, keys( %{ $fields_lookup } ) );

    my $csv = MediaWords::TM::Dump::_get_hashes_as_encoded_csv( $stories, $fields );

    return $csv;
}

# Get an encoded csv snapshot of the medium_links in the given timespan.
sub _get_medium_links_csv
{
    my ( $db, $timespan ) = @_;

    my $csv = MediaWords::TM::Dump::_get_query_as_csv( $db, <<SQL
        SELECT
            ml.source_media_id,
            sm.name AS source_name,
            sm.url AS source_url,
            ml.ref_media_id,
            rm.name AS ref_name,
            rm.url AS ref_url,
            ml.link_count
        FROM
            snapshot_medium_links AS ml,
            media AS sm,
            media AS rm
        WHERE
            ml.source_media_id = sm.media_id AND
            ml.ref_media_id = rm.media_id
SQL
    );

    return $csv;
}

# Get an encoded csv snapshot of the media in the given timespan.
sub _get_media_csv
{
    my ( $db, $timespan ) = @_;

    my $res = $db->query( <<SQL
        SELECT
            m.name,
            m.url,
            mlc.*
        FROM
            snapshot_media AS m,
            snapshot_medium_link_counts AS mlc
        WHERE m.media_id = mlc.media_id
        ORDER BY mlc.media_inlink_count DESC
SQL
    );

    my $fields = $res->columns;
    my $media  = $res->hashes;

    my $extra_fields = MediaWords::TM::Snapshot::ExtraFields::add_extra_fields_to_snapshot_media( $db, $timespan, $media );

    push( @{ $fields }, @{ $extra_fields } );

    my $csv = MediaWords::TM::Dump::_get_hashes_as_encoded_csv( $media, $fields );

    return $csv;
}

sub main
{
    my ( $timespans_id ) = @ARGV;

    die( "usage: $0 <timespans_id>" ) unless ( $timespans_id );

    my $db = MediaWords::DB::connect_to_db();

    my $timespan = $db->find_by_id( "timespans", $timespans_id )
      || die( "no timespan found for $timespans_id" );

    DEBUG( "setting up snapshot ..." );
    MediaWords::TM::Snapshot::Views::setup_temporary_snapshot_views( $db, $timespan );

    DEBUG( "dumping stories ..." );
    my $stories_csv = _get_stories_csv( $db, $timespan );
    write_file( "stories_${ timespans_id }.csv", \$stories_csv );

    DEBUG( "dumping media ..." );
    my $media_csv = _get_media_csv( $db, $timespan );
    write_file( "media_${ timespans_id }.csv", \$media_csv );

    # DEBUG( "dumping story links ..." );
    # my $story_links_csv = _get_story_links_csv( $db, $timespan );
    # write_file( "story_links_${ timespans_id }.csv", \$story_links_csv );

    DEBUG( "dumping medium_links ..." );
    my $medium_links_csv = _get_medium_links_csv( $db, $timespan );
    write_file( "medium_links_${ timespans_id }.csv", \$medium_links_csv );

    DEBUG( "dumping medium_tags ..." );
    my $medium_tags_csv = MediaWords::TM::Dump::_get_query_as_csv( $db, <<SQL
        SELECT
            mtm.media_id,
            t.tags_id,
            t.tag,
            t.label,
            t.tag_sets_id,
            ts.name AS tag_set_name
        FROM snapshot_medium_link_counts AS mlc
            JOIN snapshot_media_tags_map AS mtm USING ( media_id )
            JOIN tags AS t USING (tags_id)
            JOIN tag_sets AS ts USING (tag_sets_id)
SQL
    );
    write_file( "medium_tags_${ timespans_id }.csv", \$medium_tags_csv );
}

main();
