from mediawords.db import DatabaseHandler

# All tables that get stored as snapshot_* for each snapshot
__SNAPSHOT_TABLES = [
    'topic_stories',
    'topic_links_cross_media',
    'topic_media_codes',
    'stories media',
    'stories_tags_map',
    'media_tags_map',
    'tags',
    'tag_sets',
    'tweet_stories',
]

# All tables that get stories as snapshot_* for each timespan
__TIMESPAN_TABLES = [
    'story_link_counts',
    'story_links',
    'medium_link_counts',
    'medium_links',
    'timespan_tweets',
]


def create_temporary_snapshot_views(db: DatabaseHandler, timespan: dict) -> None:
    """Create temporary view of all the snapshot_* tables that call into the snap.* tables.

    This is useful for writing queries on the snap.* tables without lots of ugly joins and clauses to cd and timespan.
    It also provides the same set of snapshot_* tables as provided by write_story_link_counts_snapshot_tables, so that
    the same set of queries can run against either."""

    # PostgreSQL prints lots of 'NOTICE's when deleting temporary tables
    db.set_print_warn(False)

    for table in __SNAPSHOT_TABLES:
        db.query(f"""
            CREATE TEMPORARY VIEW snapshot_{table} AS
                SELECT *
                FROM snap.$t
                WHERE snapshots_id = %(snapshots_id)s
        """, {'snapshots_id': timespan['snapshots_id']})

    for table in __TIMESPAN_TABLES:
        db.query(f"""
            CREATE TEMPORARY VIEW snapshot_{table} AS
                SELECT *
                FROM snap.$t
                WHERE timespans_id = %(timespans_id)s
        """, {'timespans_id': timespan['timespans_id']})

    db.query("""
        CREATE TEMPORARY VIEW snapshot_period_stories AS
            SELECT stories_id
            FROM snapshot_story_link_counts
    """)

    add_media_type_views(db)

    # Set the warnings back on
    db.set_print_warn(True)


def add_media_type_views(db: DatabaseHandler) -> None:
    # noinspection SqlResolve
    db.query("""
        CREATE OR REPLACE VIEW snapshot_media_with_types AS

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
                            ON umtm.tags_id = ut.tags_id
                )
                    ON m.media_id = umtm.media_id
                LEFT JOIN (
                    snapshot_tags AS ct
                        JOIN snapshot_media_tags_map AS cmtm
                            ON cmtm.tags_id = ct.tags_id
                        JOIN topics AS c
                            ON c.media_type_tag_sets_id = ct.tag_sets_id
                        JOIN topics_id AS cid
                            ON c.topics_id = cid.topics_id
                )
                    ON m.media_id = cmtm.media_id
    """)

    # noinspection SqlResolve
    db.query("""
        CREATE OR REPLACE VIEW snapshot_stories_with_types AS
            SELECT
                s.*,
                m.media_type
            FROM snapshot_stories AS s
                JOIN snapshot_media_with_types AS m
                    ON s.media_id = m.media_id
    """)
