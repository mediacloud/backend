import random

from mediawords.db.handler import DatabaseHandler
from mediawords.dbi.downloads import store_content
from mediawords.dbi.stories.stories import extract_and_process_story
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed, decode_str_from_bytes_if_needed
from mediawords.util.url import get_url_host

log = create_logger(__name__)


def create_download_for_feed(db: DatabaseHandler, feed: dict) -> dict:
    feed = decode_object_from_bytes_if_needed(feed)

    priority = 0
    if 'last_attempted_download_time' not in feed:
        priority = 10

    host = get_url_host(url=feed['url'])

    return db.create(
        table='downloads',
        insert_hash={
            'feeds_id': int(feed['feeds_id']),
            'url': feed['url'],
            'host': host,
            'type': 'feed',
            'sequence': 1,
            'state': 'pending',
            'priority': priority,
            'download_time': 'NOW()',
            'extracted': False,
        })


class McCreateTestStoryStack(Exception):
    """create_test_story_stack() exception."""
    pass


def create_test_medium(db: DatabaseHandler, label: str) -> dict:
    """Create test medium with a simple label."""

    label = decode_object_from_bytes_if_needed(label)

    return db.create(
        table='media',
        insert_hash={
            'name': label,
            'url': "http://media.test/%s" % (label,),
            'is_monitored': True,
            'public_notes': "%s public notes" % (label,),
            'editor_notes': "%s editor notes" % (label,),
        })


def create_test_feed(db: DatabaseHandler, label: str, medium: dict) -> dict:
    """Create test feed with a simple label belonging to medium."""

    label = decode_object_from_bytes_if_needed(label)
    medium = decode_object_from_bytes_if_needed(medium)

    return db.create(
        table='feeds',
        insert_hash={
            'name': label,
            'url': "http://feed.test/%s" % label,
            'media_id': int(medium['media_id']),
        }
    )


def create_test_story(db: DatabaseHandler, label: str, feed: dict) -> dict:
    """Create test story with a simple label belonging to feed."""

    label = decode_object_from_bytes_if_needed(label)
    feed = decode_object_from_bytes_if_needed(feed)

    story = db.create(
        table='stories',
        insert_hash={
            'media_id': int(feed['media_id']),
            'url': "http://story.test/%s" % label,
            'guid': "guid://story.test/%s" % label,
            'title': "story %s" % label,
            'description': "description %s" % label,
            'publish_date': '2016-10-15 08:00:00',
            'collect_date': '2016-10-15 10:00:00',
            'full_text_rss': True,
        }
    )

    db.create(
        table='feeds_stories_map',
        insert_hash={
            'feeds_id': int(feed['feeds_id']),
            'stories_id': int(story['stories_id']),
        }
    )

    return story


def create_test_story_stack(db: DatabaseHandler, data: dict) -> dict:
    """Create structure of media, feeds, and stories from hash.

    Given a hash in this form:

        data = {
            'A': {
                'B': [ 1, 2 ],
                'C': [ 4 ],
            },
        }

    returns the list of media sources created, with a feeds field on each medium and a stories field on each field, all
    referenced by the given labels, in this form:

        {
            'A': {
                # medium_a_hash here,
                'feeds': {
                    'B'; {
                        # feed_b_hash here,
                        'stories: {
                            1: {
                                # story_1_hash here
                            },
                            2: {
                                # story_2_hash here
                            },
                        }
                    }
                },
            },
            'B': {
                # feed_b_hash here
            },
            1: {
                # story_1_hash here
            },
            2: {
                # story_2_hash here
            },
        }

    so, for example, story 2 can be accessed in the return value as either:

        $data[ 'A' ][ 'feeds' ][ 'B' ][ 'stories' ][ 2 ]

    or simply as:

        $data[ 2 ]

    """
    # FIXME rewrite to accept object parameters and return objects

    data = decode_object_from_bytes_if_needed(data)

    if not isinstance(data, dict):
        raise McCreateTestStoryStack("invalid media data format")

    media = {}
    for medium_label, feeds in data.items():

        medium_label = str(medium_label)

        if medium_label in media:
            raise McCreateTestStoryStack("%s medium label already used in story stack" % medium_label)

        medium = create_test_medium(db=db, label=medium_label)
        media[medium_label] = medium
        media[medium_label]['feeds'] = {}

        if not isinstance(data, dict):
            raise McCreateTestStoryStack("invalid feeds data format")

        for feed_label, story_labels in feeds.items():

            feed_label = str(feed_label)

            if feed_label in media:
                raise McCreateTestStoryStack("%s feed label already used in story stack" % feed_label)

            feed = create_test_feed(db=db, label=feed_label, medium=medium)
            media[medium_label]['feeds'][feed_label] = feed
            media[medium_label]['feeds'][feed_label]['stories'] = {}
            media[feed_label] = feed
            media[feed_label]['stories'] = {}

            if not isinstance(story_labels, list):
                raise McCreateTestStoryStack("invalid stories data format")

            for story_label in story_labels:

                story_label = str(story_label)

                if story_label in media:
                    raise McCreateTestStoryStack("%s story label already used in story stack" % story_label)

                story = create_test_story(db=db, label=story_label, feed=feed)
                media[medium_label]['feeds'][feed_label]['stories'][story_label] = story
                media[feed_label]['stories'][story_label] = story
                media[story_label] = story

    return media


def create_test_story_stack_numerated(db: DatabaseHandler,
                                      num_media: int,
                                      num_feeds_per_medium: int,
                                      num_stories_per_feed: int,
                                      label: str = 'test'):
    """Call create_test_story_stack with num_media, num_feeds_per_medium, num_stories_per_feed instead of dict."""
    if label is None:  # perl can pass undef / None explicitly so that label ends up without default
        label = 'test'
    label = str(decode_str_from_bytes_if_needed(label))

    feed_index = 0
    story_index = 0

    definition = {}

    for i in range(num_media):

        feeds = dict()
        for j in range(num_feeds_per_medium):
            feed_label = "feed_%s_%d" % (label, feed_index,)
            feed_index = feed_index + 1

            feeds[feed_label] = []

            for n in range(num_stories_per_feed):
                story_label = "story_%d" % story_index
                story_index = story_index + 1

                feeds[feed_label].append(story_label)

        media_label = "media_%s_%d" % (label, i,)
        definition[media_label] = feeds

    return create_test_story_stack(db=db, data=definition)


def create_test_topic(db: DatabaseHandler, label: str) -> dict:
    """Create test topic with a simple label."""

    label = decode_object_from_bytes_if_needed(label)

    return db.create(
        table='topics',
        insert_hash={
            'name': label,
            'description': label,
            'pattern': label,
            'solr_seed_query': label,
            'solr_seed_query_run': True,
            'start_date': '2016-01-01',
            'end_date': '2016-03-01',
            'job_queue': 'mc',
            'max_stories': 100000,
        }
    )


def _get_test_content() -> str:
    """Generated 1 - 10 paragraphs of 1 - 5 sentences of random text."""
    # No need to install, import and use Lipsum for that

    test_sentence = 'The quick brown fox jumps over the lazy dog. '

    text = ""
    for _ in range(random.randint(1, 10)):
        text += "<p>\n{}\n</p>\n\n".format((test_sentence * random.randint(1, 5)).strip())

    text = text.strip()

    return text


class McAddContentToTestStoryException(Exception):
    """add_content_to_test_story() exception."""
    pass


def add_content_to_test_story(db: DatabaseHandler, story: dict, feed: dict) -> dict:
    """Adds a 'download' and a 'content' field to each story in the test story stack. Stores the content in the download
    store. Uses the story->{ content } field if present or otherwise generates the content using _get_test_content()."""

    story = decode_object_from_bytes_if_needed(story)
    feed = decode_object_from_bytes_if_needed(feed)

    if 'content' in story:
        content = story['content']
    else:
        content = _get_test_content()

    if story.get('full_text_rss', None):
        story['full_text_rss'] = False
        db.update_by_id(
            table='stories',
            object_id=story['stories_id'],
            update_hash={'full_text_rss': False},
        )

    host = get_url_host(feed['url'])

    download = db.create(
        table='downloads',
        insert_hash={
            'feeds_id': feed['feeds_id'],
            'url': story['url'],
            'host': host,
            'type': 'content',
            'sequence': 1,
            'state': 'fetching',
            'priority': 1,
            'extracted': False,
            'stories_id': story['stories_id'],
        }
    )

    download = store_content(db=db, download=download, content=content)

    story['download'] = download
    story['content'] = content

    extract_and_process_story(db=db, story=story)

    story['download_text'] = db.query("""
        SELECT *
        FROM download_texts
        WHERE downloads_id = %(downloads_id)s
    """, {'downloads_id': download['downloads_id']}).hash()

    if not story['download_text']:
        raise McAddContentToTestStoryException("Unable to find download_text")

    return story


def add_content_to_test_story_stack(db: DatabaseHandler, story_stack: dict) -> dict:
    """Add a download and store its content for each story in the test story stack as returned from
    create_test_story_stack(). Also extract and vector each download."""

    story_stack = decode_object_from_bytes_if_needed(story_stack)

    log.debug("Adding content to test story stack ...")

    # We pseudo-randomly generate test content, but we want repeatable tests
    #
    # FIXME not sure if this works in Python when done like that (probably random.Random object would have to be passed
    # around), and is a weird idea anyway
    # srand( 3 );

    for medium_key, medium in story_stack.items():
        for feed_key, feed in medium['feeds']:
            for story_key, story in feed['stories']:
                story = add_content_to_test_story(db=db, story=story, feed=feed)

                # MC_REWRITE_TO_PYTHON: remove type checker comment after rewrite to Python
                # noinspection PyTypeChecker
                story_stack[medium_key]['feeds'][feed_key]['stories'][story_key] = story

    return story_stack
