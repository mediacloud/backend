package MediaWords::TM::Snapshot::Views;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;


# Setup snapshot_* views by creating views for the relevant snap.* tables.
#
# this is useful for writing queries on the snap.* tables without lots of ugly
# joins and clauses to snap and timespan.  It also provides the same set of
# snapshot_* views as provided by write_story_link_counts_snapshot, so that the
# same set of queries can run against either.
#
# The following snapshot_ views are created that contain a copy of all relevant
# rows present in the topic at the time the snapshot was created:
#
# * snapshot_topic_stories
# * snapshot_stories
# * snapshot_media
# * snapshot_topic_links_cross_media
# * snapshot_stories_tags_map
# * snapshot_stories_tags_map
# * snapshot_tag_sets
# * snapshot_media_with_types
#
# The data in each of these views consists of data related to all of the
# stories in the entire topic, not restricted to a specific timespan. So
# snapshot_media includes all media including any story in the topic,
# regardless of date. Each of these views consists of the fields present in the
# snapshot's view.
#
# The following snapshot_ views are created that contain data relevant only to
# the specific timespan and including the following fields:
#
# * snapshot_medium_links:
#     * source_media_id
#     * ref_media_id
#
# * snapshot_story_links:
#     * source_stories_id
#     * ref_stories_id
#
# * snapshot_medium_link_counts:
#     * media_id
#     * inlink_count
#     * outlink_count
#     * story_count
#
# * snapshot_story_link_counts:
#     * stories_id
#     * inlink_count
#     * outlink_count
#     * citly_click_count
#
sub setup_temporary_snapshot_views($$)
{
    my ( $db, $timespan ) = @_;

    # postgres prints lots of 'NOTICE's when deleting temp tables
    $db->set_print_warn( 0 );

    for my $t ( @{ _get_snapshot_tables() } )
    {
        $db->query( <<"SQL" );
            CREATE TEMPORARY VIEW snapshot_$t AS
                SELECT *
                FROM snap.$t
                WHERE snapshots_id = $timespan->{ snapshots_id }
SQL
    }

    for my $t ( @{ _get_timespan_tables() } )
    {
        $db->query( <<"SQL" )
            CREATE TEMPORARY VIEW snapshot_$t AS
                SELECT *
                FROM snap.$t
                WHERE timespans_id = $timespan->{ timespans_id }
SQL
    }

    $db->query( <<SQL
        CREATE TEMPORARY VIEW snapshot_period_stories AS
            SELECT stories_id
            FROM snapshot_story_link_counts
SQL
    );

    add_media_type_views( $db );
}

# Runs $db->query( "discard temp" ) to clean up temporary tables and views.
# This should be run after calling setup_temporary_snapshot_views(). Calling
# setup_temporary_snapshot_views() within a transaction and committing the
# transaction will have the same effect.
sub discard_temp_tables_and_views
{
    my ( $db ) = @_;

    $db->query( "discard temp" );
}

sub add_media_type_views
{
    my ( $db ) = @_;

    $db->query( <<SQL

        CREATE OR REPLACE TEMPORARY VIEW snapshot_media_with_types AS
            WITH topics_id AS (
                SELECT topics_id
                FROM snapshot_topic_stories
                LIMIT 1
            )

            SELECT
                m.*,
                CASE
                    WHEN (ct.label != 'Not Typed') THEN ct.label
                    WHEN (ut.label IS NOT NULL) THEN ut.label
                    ELSE 'Not Typed'
                END AS media_type

            FROM snapshot_media AS m

                LEFT JOIN (
                    snapshot_tags AS ut

                        JOIN snapshot_tag_sets AS uts
                            ON ut.tag_sets_id = uts.tag_sets_id
                           AND uts.name = 'media_type'

                        JOIN snapshot_media_tags_map AS umtm
                            on umtm.tags_id = ut.tags_id

                ) ON m.media_id = umtm.media_id

                LEFT JOIN (
                    snapshot_tags AS ct

                        JOIN snapshot_media_tags_map AS cmtm
                            ON cmtm.tags_id = ct.tags_id
                        JOIN topics AS c
                            ON c.media_type_tag_sets_id = ct.tag_sets_id
                        JOIN topics_id AS cid
                            ON c.topics_id = cid.topics_id
                ) ON m.media_id = cmtm.media_id

SQL
    );

    $db->query( <<SQL );
        CREATE OR REPLACE TEMPORARY VIEW snapshot_stories_with_types AS
            SELECT
                s.*,
                m.media_type
            FROM snapshot_stories AS s
                JOIN snapshot_media_with_types AS m
                    ON s.media_id = m.media_id
SQL

}

1;
