from typing import Optional

from mediawords.db import DatabaseHandler
from mediawords.util.guess_date import GUESS_METHOD_TAG_SET, INVALID_TAG_SET


def get_story_date_tag(db: DatabaseHandler, story: dict) -> Optional[tuple]:
    """Return the tag tag_sets dict associated with the story guess method tag sets."""
    tags = db.query(
        """
        select t.*
            from tags t
                join tag_sets ts using ( tag_sets_id )
                join stories_tags_map stm using ( tags_id )
            where
                ts.name = any(%(a)s) and
                stm.stories_id = %(b)s
        """,
        {
            'a': [GUESS_METHOD_TAG_SET, INVALID_TAG_SET],
            'b': story['stories_id']
        }).hashes()

    assert len(tags) < 2

    if len(tags) == 1:
        tag = tags[0]
    else:
        return None, None

    tag_set = db.require_by_id('tag_sets', tag['tag_sets_id'])

    return tag, tag_set
