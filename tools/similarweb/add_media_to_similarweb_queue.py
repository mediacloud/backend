#!/usr/bin/env python3

from mediawords.db import DatabaseHandler, connect_to_db
from mediawords.job.similarweb.update_estimated_visits import UpdateEstimatedVisitsJob
from mediawords.util.log import create_logger

log = create_logger(__name__)


def add_media_to_similarweb_queue(db: DatabaseHandler) -> None:
    log.info("Fetching media to add to SimilarWeb queue...")
    media = db.query("""
        SELECT media_id
        FROM (
            SELECT DISTINCT
                media.media_id,
                (
                    mtm_retweet_partisanship.tags_id IS NOT NULL
                ) AS belongs_to_retweet_partisanship,
                (
                    mtm_abyz_collection.tags_id IS NOT NULL
                    AND media_health.media_health_id IS NOT NULL
                    AND media_health.num_stories_y > 0
                ) AS belongs_to_abyz_collection_with_stories,
                (
                    mtm_emm_collection.tags_id IS NOT NULL
                    AND media_health.media_health_id IS NOT NULL
                    AND media_health.num_stories_y > 0
                ) AS belongs_to_emm_collection_with_stories,
                (
                    mtm_collection.tags_id IS NOT NULL
                    AND media_health.media_health_id IS NOT NULL
                    AND media_health.num_stories_y > 0
                ) AS belongs_to_collection_with_stories,
                (
                    mtm_abyz_collection.tags_id IS NOT NULL
                ) AS belongs_to_abyz_collection,
                (
                    mtm_emm_collection.tags_id IS NOT NULL
                ) AS belongs_to_emm_collection,
                (
                    mtm_collection.tags_id IS NOT NULL
                ) AS belongs_to_collection
            FROM media

                LEFT JOIN media_tags_map AS mtm_emm_collection
                    ON media.media_id = mtm_emm_collection.media_id
                   AND mtm_emm_collection.tags_id IN (
                        SELECT tags_id
                        FROM tags
                        WHERE tag_sets_id IN (
                            SELECT tag_sets_id
                            FROM tag_sets
                            WHERE name LIKE 'emm_%'
                        )
                   )

                LEFT JOIN media_tags_map AS mtm_abyz_collection
                    ON media.media_id = mtm_abyz_collection.media_id
                   AND mtm_abyz_collection.tags_id IN (
                        SELECT tags_id
                        FROM tags
                        WHERE tag_sets_id = (
                            SELECT tag_sets_id
                            FROM tag_sets
                            WHERE name = 'ABYZ'
                        )
                   )
            
                LEFT JOIN media_tags_map AS mtm_collection
                    ON media.media_id = mtm_collection.media_id
                   AND mtm_collection.tags_id IN (
                        SELECT tags_id
                        FROM tags
                        WHERE tag_sets_id = (
                            SELECT tag_sets_id
                            FROM tag_sets
                            WHERE name = 'collection'
                        )
                   )

                LEFT JOIN media_tags_map AS mtm_retweet_partisanship
                    ON media.media_id = mtm_retweet_partisanship.media_id
                   AND mtm_retweet_partisanship.tags_id IN (
                        SELECT tags_id
                        FROM tags
                        WHERE tag_sets_id IN (
                            SELECT tag_sets_id
                            FROM tag_sets
                            WHERE name LIKE 'retweet_partisanship_%'
                        )
                   )

                LEFT JOIN media_health
                    ON media.media_id = media_health.media_id

            ORDER BY
                belongs_to_retweet_partisanship DESC,           -- 't' first
                belongs_to_abyz_collection_with_stories DESC,   -- 't' first
                belongs_to_emm_collection_with_stories DESC,    -- 't' first
                belongs_to_collection_with_stories DESC,        -- 't' first
                belongs_to_abyz_collection DESC,                -- 't' first
                belongs_to_emm_collection DESC,                 -- 't' first
                belongs_to_collection DESC,                     -- 't' first
                media.media_id ASC
        ) AS prioritized_media
    """).flat()
    log.info("Done fetching media to add to SimilarWeb queue.")

    log.info("Adding media IDs to SimilarWeb queue...")
    x = 0
    for media_id in media:
        log.info(f"Adding media ID {media_id} to SimilarWeb queue...")
        UpdateEstimatedVisitsJob.add_to_queue(media_id=media_id)

        x += 1
        if x % 1000 == 0:
            log.info(f"Added {x} / {len(media)} media IDs to SimilarWeb queue.")

    log.info(f"Done adding media IDs to SimilarWeb queue, added {len(media)} media IDs.")


if __name__ == '__main__':
    db_ = connect_to_db()
    add_media_to_similarweb_queue(db_)
