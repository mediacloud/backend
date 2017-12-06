from mediawords.db import DatabaseHandler
from mediawords.util.perl import decode_object_from_bytes_if_needed


def is_new(db: DatabaseHandler, story: dict) -> bool:
    """Return true if this story should be considered new for the given media source.

    A story is new if no story with the same url or guid exists in the same media
    source and if no story exists with the same title in the same media source in
    the same calendar day."""

    story = decode_object_from_bytes_if_needed(story)

    if story['title'] == '(no title)':
        return False

    db_story = db.query("""
        SELECT *
        FROM stories
        WHERE guid = %(guid)s
          AND media_id = %(media_id)s
    """, {
        'guid': story['guid'],
        'media_id': int(story['media_id'])
    }).hash()

    if db_story is not None:
        return False

    db_story = db.query("""
        SELECT 1
        FROM stories
        WHERE md5(title) = md5(%(story_title)s)
          AND media_id = %(media_id)s
          
          -- We do the goofy " + interval '1 second'" to force postgres to use the stories_title_hash index
          AND date_trunc('day', publish_date) + INTERVAL '1 second' =
              date_trunc('day', %(publish_date)s::date) + INTERVAL '1 second'
              
        -- FIXME why "FOR UPDATE"?
        FOR UPDATE
    """, {
        'story_title': story['title'],
        'media_id': int(story['media_id']),
        'publish_date': story['publish_date'],
    }).hash()

    if db_story is not None:
        return False

    return True
