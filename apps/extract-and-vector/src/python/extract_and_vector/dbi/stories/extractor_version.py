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

    # MC_CITUS_SHARDING_UPDATABLE_VIEW_HACK
    db.query("""
        DELETE FROM unsharded_public.stories_tags_map
        WHERE
            stories_id = %(stories_id)s AND
            tags_id IN (
                SELECT tags_id
                FROM tags
                WHERE tag_sets_id = %(tag_sets_id)s
            )
    """, {
        'tag_sets_id': tag_set['tag_sets_id'],
        'stories_id': stories_id,
    })
    db.query("""
        DELETE FROM sharded_public.stories_tags_map
        WHERE
            stories_id = %(stories_id)s AND
            tags_id IN (
                SELECT tags_id
                FROM tags
                WHERE tag_sets_id = %(tag_sets_id)s
            )
    """, {
        'tag_sets_id': tag_set['tag_sets_id'],
        'stories_id': stories_id,
    })

    tag = db.find_or_create(table='tags', insert_hash={'tag': extractor_version, 'tag_sets_id': tag_set['tag_sets_id']})
    tags_id = tag['tags_id']

    # MC_CITUS_SHARDING_UPDATABLE_VIEW_HACK: restore ON CONFLICT after rows get moved
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
            INSERT INTO public.stories_tags_map (stories_id, tags_id)
            VALUES (%(stories_id)s, %(tags_id)s)
        """, {
            'stories_id': stories_id,
            'tags_id': tags_id,
        })
