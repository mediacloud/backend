from mediawords.db import DatabaseHandler


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
