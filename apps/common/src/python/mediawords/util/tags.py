"""
Various functions for editing feed and medium tags.
"""

# FIXME move everything to "Tags" / "Tag sets" models?
import re
from typing import Dict, Any, Optional, Tuple

from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


def _tag_set_tag(tag_name: str) -> Optional[Tuple[str, str]]:
    tag_name = decode_object_from_bytes_if_needed(tag_name)

    if not tag_name:
        log.warning("Tag name is empty.")
        return None

    if not re.match(pattern='^([^:]*):([^:]*)$', string=tag_name):
        log.warning("Unable to parse tag name '{}'.".format(tag_name))
        return None

    tag_set_name, tag = tag_name.split(':')

    return tag_set_name, tag


def lookup_tag(db: DatabaseHandler, tag_name: str) -> Optional[Dict[str, Any]]:
    """Lookup the tag given the "tag_set:tag" format."""
    tag_name = decode_object_from_bytes_if_needed(tag_name)

    tag_set_tag = _tag_set_tag(tag_name)
    if not tag_set_tag:
        return None

    (tag_set_name, tag) = tag_set_tag

    found_tag = db.query("""
        SELECT t.*
        FROM tags AS t,
             tag_sets AS ts
        WHERE t.tag_sets_id = ts.tag_sets_id
          AND t.tag = %(tag)s
          AND ts.name = %(tag_set_name)s
    """, {'tag': tag, 'tag_set_name': tag_set_name}).hash()

    # MC_REWRITE_TO_PYTHON: Perlism
    if found_tag is None:
        found_tag = {}

    return found_tag


def lookup_or_create_tag(db: DatabaseHandler, tag_name: str) -> Optional[Dict[str, Any]]:
    """Lookup the tag given the "tag_set:tag" format. Create it if it does not already exist."""
    tag_name = decode_object_from_bytes_if_needed(tag_name)

    tag_set_tag = _tag_set_tag(tag_name)
    if not tag_set_tag:
        return None

    (tag_set_name, tag) = tag_set_tag

    tag_set = db.find_or_create(table='tag_sets', insert_hash={'name': tag_set_name})
    tag = db.find_or_create(table='tags', insert_hash={'tag': tag, 'tag_sets_id': tag_set['tag_sets_id']})

    return tag


def assign_singleton_tag_to_medium(db: DatabaseHandler,
                                   medium: Dict[str, Any],
                                   tag_set: Dict[str, Any],
                                   tag: Dict[str, Any]) -> None:
    """
    Assign the given tag in the given tag set to the given medium.

    If the tag or tag set does not exist, create it.
    """
    medium = decode_object_from_bytes_if_needed(medium)
    tag_set = decode_object_from_bytes_if_needed(tag_set)
    tag = decode_object_from_bytes_if_needed(tag)

    tag_set = db.find_or_create(table='tag_sets', insert_hash=tag_set)

    tag['tag_sets_id'] = tag_set['tag_sets_id']

    # Don't just use find_or_create() here, because we want to find only on the actual "tags.tag" value, not the rest of
    # the tag metadata
    db_tag = db.query("""
        SELECT *
        FROM tags
        WHERE tag_sets_id = %(tag_sets_id)s
          AND tag = %(tag)s
    """, {
        'tag_sets_id': tag['tag_sets_id'],
        'tag': tag['tag'],
    }).hash()
    if not db_tag:
        db_tag = db.create(table='tags', insert_hash=tag)

    tag = db_tag

    # Make sure we only update the tag in the database if necessary; otherwise we will trigger Solr re-imports
    # unnecessarily
    existing_tag = db.query("""
        SELECT t.*
        FROM tags AS t
            JOIN media_tags_map AS mtm USING (tags_id)
        WHERE t.tag_sets_id = %(tag_sets_id)s
          AND mtm.media_id = %(media_id)s
    """, {
        'tag_sets_id': tag_set['tag_sets_id'],
        'media_id': medium['media_id'],
    }).hash()

    if existing_tag and existing_tag['tags_id'] == tag['tags_id']:
        return

    if existing_tag:
        db.query("""
            DELETE FROM media_tags_map
            WHERE tags_id = %(tags_id)s
              AND media_id = %(media_id)s
        """, {
            'tags_id': existing_tag['tags_id'],
            'media_id': medium['media_id'],
        })

    db.query("""
        INSERT INTO media_tags_map (tags_id, media_id)
        VALUES (%(tags_id)s, %(media_id)s)
        ON CONFLICT (media_id, tags_id) DO NOTHING
    """, {
        'tags_id': tag['tags_id'],
        'media_id': medium['media_id'],
    })
