from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium, create_test_feed, create_test_story
from topics_base.stories import get_preferred_story


def test_get_preferred_story():
    """Test get_preferred_story()."""
    db = connect_to_db()

    num_media = 5
    media = []
    for i in range(num_media):
        medium = create_test_medium(db, "foo " + str(i))
        feed = create_test_feed(db=db, label="foo", medium=medium)
        story = create_test_story(db=db, label="foo", feed=feed)
        medium['story'] = story
        media.append(medium)

    # first prefer medium pointed to by dup_media_id of another story
    preferred_medium = media[1]
    db.query("""
        UPDATE media SET
            dup_media_id = %(dup_media_id)s
        WHERE media_id = %(media_id)s
    """, {
        'dup_media_id': preferred_medium['media_id'],
        'media_id': media[0]['media_id'],
    })

    stories = [m['story'] for m in media]
    assert get_preferred_story(db, stories) == preferred_medium['story']

    # next prefer any medium without a dup_media_id
    preferred_medium = media[num_media - 1]
    # noinspection SqlWithoutWhere
    db.query("UPDATE media SET dup_media_id = NULL")
    db.query("""
        UPDATE media SET
            dup_media_id = %(media_id)s
        WHERE media_id != %(media_id)s
    """, {
        'media_id': media[0]['media_id'],
    })
    db.query("""
        UPDATE media SET
            dup_media_id = NULL
        WHERE media_id = %(media_id)s
    """, {
        'media_id': preferred_medium['media_id'],
    })
    stories = [m['story'] for m in media[1:]]
    assert get_preferred_story(db, stories) == preferred_medium['story']

    # next prefer the medium whose story url matches the medium domain
    db.query("""
        UPDATE media SET
            dup_media_id = NULL
        WHERE media_id > 0
    """)

    for medium in media:
        db.query("""
            UPDATE media SET
                url = %(url)s
            WHERE media_id = %(media_id)s
        """, {
            'url': f"http://media-{medium['media_id']}.com",
            'media_id': medium['media_id'],
        })

    for story in stories:
        # MC_CITUS_SHARDING_UPDATABLE_VIEW_HACK: test should write only to the sharded table
        db.query("""
            UPDATE sharded_public.stories SET
                url = %(url)s
            WHERE stories_id = %(stories_id)s
        """, {
            'url': f"http://stories-{story['stories_id']}.com",
            'stories_id': story['stories_id'],
        })

    preferred_medium = media[2]

    # MC_CITUS_SHARDING_UPDATABLE_VIEW_HACK: test should write only to the sharded table
    db.query("""
        WITH stories_to_update AS (
            SELECT stories_id
            FROM stories
            WHERE media_id = %(media_id)s
        )
        UPDATE sharded_public.stories SET
            url = %(url)s
        WHERE stories_id IN (
            SELECT stories_id
            FROM stories_to_update
        )
    """, {
            'url': f"http://media-{preferred_medium['media_id']}.com",
            'media_id': preferred_medium['media_id'],
        }
    )

    stories = db.query("SELECT * FROM stories").hashes()
    preferred_story = db.query("""
        SELECT *
        FROM stories
        WHERE media_id = %(media_id)s
    """, {
        'media_id': preferred_medium['media_id'],
    }).hash()

    assert get_preferred_story(db, stories) == preferred_story

    # next prefer lowest media_id
    # MC_CITUS_SHARDING_UPDATABLE_VIEW_HACK: test should write only to the sharded table
    for story in stories:
        db.query("""
            UPDATE sharded_public.stories SET
                url = %(url)s
            WHERE stories_id = %(stories_id)s
        """, {
            'url': f"http://stories-{story['stories_id']}.com",
            'stories_id': story['stories_id'],
        })

    stories = db.query("SELECT * FROM stories").hashes()
    assert get_preferred_story(db, stories)['stories_id'] == media[0]['story']['stories_id']
