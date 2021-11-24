from mediawords.db import DatabaseHandler
from mediawords.util.perl import decode_object_from_bytes_if_needed


def extractor_version_tag_sets_name() -> str:
    return 'extractor_version'


def update_extractor_version_tag(db: DatabaseHandler, stories_id: int, extractor_version: str) -> None:
    """Add extractor version tag to the story."""
    # FIXME no caching because unit tests run in the same process so a cached tag set / tag will not be recreated.
    # Purging such a cache manually is very error-prone.

    if isinstance(stories_id, bytes):
        stories_id = decode_object_from_bytes_if_needed(stories_id)
    stories_id = int(stories_id)

    extractor_version = decode_object_from_bytes_if_needed(extractor_version)

    tag_set = db.find_or_create(table='tag_sets', insert_hash={'name': extractor_version_tag_sets_name()})

    db.query("""
        DELETE FROM stories_tags_map AS stm
            USING tags AS t
                JOIN tag_sets AS ts
                    ON ts.tag_sets_id = t.tag_sets_id
        WHERE t.tags_id = stm.tags_id
          AND ts.tag_sets_id = %(tag_sets_id)s
          AND stm.stories_id = %(stories_id)s
    """, {
        'tag_sets_id': tag_set['tag_sets_id'],
        'stories_id': stories_id,
    })

    tag = db.find_or_create(table='tags', insert_hash={'tag': extractor_version, 'tag_sets_id': tag_set['tag_sets_id']})
    tags_id = tag['tags_id']

    # MC_CITUS_SHARDING_UPDATABLE_VIEW_HACK: upserts don't work on an
    # updatable view, and we can't upsert directly into the sharded table
    # as the duplicate row might already exist in the unsharded one;
    # therefore, we test the unsharded table once for whether the row
    # exists and do an upsert to a sharded table -- the row won't start
    # suddenly existing in an essentially read-only unsharded table so this
    # should be safe from race conditions. After migrating rows, one can
    # reset this statement to use a native upsert
    row_exists = db.query(
        """
        SELECT 1
        FROM stories_tags_map
        WHERE
            stories_id = %(stories_id)s AND
            tags_id = %(tags_id)s
        """,
        {
            'stories_id': stories_id,
            'tags_id': tags_id,
        }
    ).hash()
    if not row_exists:
        db.query("""
            INSERT INTO sharded_public.stories_tags_map (stories_id, tags_id)
            VALUES (%(stories_id)s, %(tags_id)s)
            ON CONFLICT (stories_id, tags_id) DO NOTHING
        """, {
            'stories_id': stories_id,
            'tags_id': tags_id,
        })
