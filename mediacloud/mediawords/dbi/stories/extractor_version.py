from typing import Dict, Any

from mediawords.db import DatabaseHandler
from mediawords.util.extract_text import extractor_name
from mediawords.util.perl import decode_object_from_bytes_if_needed

# Cached IDs of tags, which should change rarely
# FIXME unsure if this works with Perl-Python setup
__TAGS_ID_CACHE = {}

# Cached extractor version tag set
# FIXME unsure if this works with Perl-Python setup
__EXTRACTOR_VERSION_TAG_SET = None


def _purge_extractor_version_caches() -> None:
    """Purge cached values (used by tests)."""
    global __TAGS_ID_CACHE
    global __EXTRACTOR_VERSION_TAG_SET

    __TAGS_ID_CACHE = {}
    __EXTRACTOR_VERSION_TAG_SET = None


def extractor_version_tag_sets_name() -> str:
    return 'extractor_version'


def _get_tags_id(db: DatabaseHandler, tag_sets_id: int, tag_name: str) -> int:
    """Get cached ID of the tag. Create the tag if necessary.

    We need this to make tag lookup very fast for add_default_tags.
    """
    if isinstance(tag_sets_id, bytes):
        tag_sets_id = decode_object_from_bytes_if_needed(tag_sets_id)
    tag_sets_id = int(tag_sets_id)
    tag_name = decode_object_from_bytes_if_needed(tag_name)

    global __TAGS_ID_CACHE

    cached_tags_id = __TAGS_ID_CACHE.get(tag_sets_id, {}).get(tag_name, None)
    if cached_tags_id is not None:
        return cached_tags_id

    tag = db.find_or_create(table='tags', insert_hash={'tag': tag_name, 'tag_sets_id': tag_sets_id})
    tags_id = tag['tags_id']

    if tag_sets_id not in __TAGS_ID_CACHE:
        __TAGS_ID_CACHE[tag_sets_id] = {}

    __TAGS_ID_CACHE[tag_sets_id][tag_name] = tags_id

    return tags_id


def _get_extractor_version_tag_set(db: DatabaseHandler) -> Dict[str, Any]:
    global __EXTRACTOR_VERSION_TAG_SET
    if __EXTRACTOR_VERSION_TAG_SET is None:
        tag_set = db.find_or_create(table='tag_sets', insert_hash={'name': extractor_version_tag_sets_name()})
        __EXTRACTOR_VERSION_TAG_SET = tag_set
    return __EXTRACTOR_VERSION_TAG_SET


def _get_current_extractor_version_tags_id(db: DatabaseHandler) -> int:
    extractor_version = extractor_name()
    tag_set = _get_extractor_version_tag_set(db=db)

    tags_id = _get_tags_id(db=db, tag_sets_id=tag_set['tag_sets_id'], tag_name=extractor_version)

    return tags_id


def update_extractor_version_tag(db: DatabaseHandler, story: dict) -> None:
    """Add extractor version tag to the story."""

    story = decode_object_from_bytes_if_needed(story)

    tag_set = _get_extractor_version_tag_set(db=db)

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
        'stories_id': story['stories_id'],
    })

    tags_id = _get_current_extractor_version_tags_id(db=db)

    db.query("""
        INSERT INTO stories_tags_map (stories_id, tags_id)
        VALUES (%(stories_id)s, %(tags_id)s)
    """, {'stories_id': story['stories_id'], 'tags_id': tags_id})
