import random
import re

from mediawords.db.handler import DatabaseHandler
from mediawords.dbi.downloads.store import store_content
from mediawords.dbi.stories.postprocess import mark_as_processed
from mediawords.languages.factory import LanguageFactory
from mediawords.util.identify_language import language_code_for_text
from mediawords.util.log import create_logger
from mediawords.util.parse_html import html_strip
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


def create_download_for_story(db: DatabaseHandler, feed: dict, story: dict) -> dict:
    feed = decode_object_from_bytes_if_needed(feed)
    story = decode_object_from_bytes_if_needed(story)

    host = get_url_host(url=feed['url'])

    return db.create(
        table='downloads',
        insert_hash={
            'feeds_id': feed['feeds_id'],
            'url': story['url'],
            'host': host,
            'type': 'content',
            'sequence': 1,
            'state': 'success',
            'priority': 1,
            'extracted': False,
            'path': 'postgresql:foo',
            'stories_id': story['stories_id'],
        }
    )


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
            'platform': 'web'
        }
    )


def create_test_snapshot(db: DatabaseHandler, topic: dict) -> dict:
    """Create simple snapshot for testing."""
    return db.create(
        table='snapshots',
        insert_hash={
            'topics_id': topic['topics_id'],
            'snapshot_date': topic['end_date'],
            'start_date': topic['start_date'],
            'end_date': topic['end_date']
        }
    )


def create_test_timespan(db: DatabaseHandler, topic: dict=None, snapshot: dict=None) -> dict:
    """Create simple timespans for testing.

    Mast pass either topic or snapshot or both. If a snapshot is not passed, create one.
    """
    assert topic is not None or snapshot is not None

    if not snapshot:
        snapshot = create_test_snapshot(db, topic)

    return db.create(
        table='timespans',
        insert_hash={
            'snapshots_id': snapshot['snapshots_id'],
            'start_date': snapshot['start_date'],
            'end_date': snapshot['end_date'],
            'period': 'overall',
            'story_count': 0,
            'story_link_count': 0,
            'medium_count': 0,
            'medium_link_count': 0,
            'post_count': 0
        }
    )


def _get_test_content() -> str:
    """Generate 1 - 10 paragraphs of 1 - 5 sentences of random text that looks like a human language.

    Generated text has to be identified as being of a certain language by the CLD."""
    # No need to install, import and use Lipsum for that (most of the available lipsum packages are barely maintained)
    # FIXME maybe move to .util.text?

    lipsum_text = """
        Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus quis lacus vel leo egestas cursus ut vel leo.
        Aenean mollis nunc sed venenatis pretium. Proin auctor vehicula magna, nec venenatis ligula pellentesque at. Sed
        in imperdiet est. Cras consectetur enim vitae mattis tristique. Nam in turpis dapibus, porttitor ex eget,
        scelerisque ante. Orci varius natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Morbi
        enim orci, facilisis at magna auctor, pharetra dapibus ante. Quisque iaculis eros suscipit nibh malesuada
        placerat. Maecenas blandit et nulla ac placerat. Ut vel turpis nec lacus finibus feugiat. Maecenas ut eros
        feugiat, rutrum dui ac, imperdiet eros. Aenean sollicitudin, orci nec facilisis maximus, sem erat venenatis
        tortor, ac malesuada ligula ante vitae elit. Mauris et posuere ipsum. Vivamus ac pulvinar enim. Integer vitae
        ipsum nec sapien viverra molestie dignissim quis lacus.

        Nulla fringilla nunc vitae euismod ultricies. Suspendisse sodales nulla nunc, in sagittis est faucibus in. Sed
        vestibulum, lacus non convallis accumsan, nisi nisi tempus ipsum, a ornare ligula neque sit amet quam. Fusce
        sagittis sed libero id luctus. Orci varius natoque penatibus et magnis dis parturient montes, nascetur ridiculus
        mus. Nulla diam erat, dictum non turpis a, rutrum scelerisque sapien. Vivamus ornare lorem et ex cursus ornare.
        Nunc tincidunt lorem quam, imperdiet finibus erat venenatis at. Fusce ligula turpis, gravida ut nisl pulvinar,
        tempor pharetra augue. Nulla ipsum nisl, fermentum ac dignissim vel, rhoncus sed dui.

        Nam sed risus interdum, sollicitudin ipsum id, sollicitudin lectus. Phasellus quam tortor, pellentesque at
        posuere in, ultricies non nisl. Morbi et aliquam dui. Ut a quam ac nisl pretium vulputate quis at arcu. Integer
        ultricies ultricies cursus. Fusce erat lorem, pellentesque vel augue viverra, pulvinar faucibus justo. Curabitur
        ut leo eu sem mollis scelerisque.

        Nulla volutpat facilisis est, non lacinia sapien ultrices aliquet. Lorem ipsum dolor sit amet, consectetur
        adipiscing elit. Vestibulum cursus enim turpis, eget egestas nulla aliquet hendrerit. Fusce gravida imperdiet
        ipsum et volutpat. Nullam convallis volutpat purus ut commodo. Suspendisse viverra ante sit amet condimentum
        interdum. Donec faucibus odio ex, eu maximus risus faucibus et. Nulla eget mollis odio. Donec finibus ante ex.
        Pellentesque ex lacus, sodales a est a, tempor tincidunt dolor. Mauris faucibus at enim sed tristique. Nullam
        posuere velit quis tristique convallis. Ut mattis, dolor quis semper laoreet, mi justo euismod diam, at tempus
        turpis nisl id felis. Nam rutrum, libero sodales cursus consequat, nulla ipsum viverra odio, vel volutpat eros
        nisl quis odio. Aliquam molestie, massa id semper imperdiet, diam massa ullamcorper massa, vel blandit arcu
        ligula in risus.

        Phasellus eros ipsum, tempor sed sapien id, sagittis egestas tortor. Sed posuere nunc vitae augue efficitur,
        eget pulvinar erat tempus. Curabitur non sollicitudin magna. Nunc efficitur placerat lorem, sit amet pulvinar
        nulla aliquam ac. Quisque mattis purus ornare neque interdum rhoncus. Suspendisse eget odio ultrices,
        sollicitudin eros a, luctus justo. Morbi ac fringilla lacus, quis placerat eros. Mauris efficitur massa risus,
        id blandit elit dignissim et.
    """

    dictionary = set([word.lower() for word in re.findall(pattern=r'\w+', string=lipsum_text)])

    text = ""
    for paragraph_count in range(random.randint(1, 10)):

        sentences_in_paragraph = []

        for sentence_in_paragraph_count in range(random.randint(1, 5)):
            sentence = ' '.join(random.sample(dictionary, k=random.randint(5, 20)))
            sentence += random.choice(['.', '?', '!'])
            sentence = sentence.capitalize()
            sentences_in_paragraph.append(sentence)

        text += "<p>\n{}\n</p>\n\n".format(' '.join(sentences_in_paragraph))

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

    content_language_code = None
    if 'content' in story:
        content = story['content']
        content_language_code = language_code_for_text(content)
    else:
        content = _get_test_content()

    # If language code was undetermined, or if we're using Latin test content
    if not content_language_code:
        content_language_code = 'en'

    if story.get('full_text_rss', None):
        story['full_text_rss'] = False
        db.update_by_id(
            table='stories',
            object_id=story['stories_id'],
            update_hash={
                'full_text_rss': False,
                'language': content_language_code,
            },
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
            'extracted': True,
            'stories_id': story['stories_id'],
        }
    )

    download = store_content(db=db, download=download, content=content)

    extracted_content = html_strip(content)

    story['download'] = download
    story['content'] = extracted_content

    db.query("""
        INSERT INTO download_texts (downloads_id, download_text, download_text_length)
        VALUES (%(downloads_id)s, %(download_text)s, CHAR_LENGTH(%(download_text)s))
    """, {
        'downloads_id': download['downloads_id'],
        'download_text': extracted_content,
    })

    lang = LanguageFactory.language_for_code(content_language_code)
    assert lang, f"Language is None for code {content_language_code}"

    sentences = lang.split_text_to_sentences(extracted_content)
    sentence_number = 1
    for sentence in sentences:
        db.insert(table='story_sentences', insert_hash={
            'sentence': sentence,
            'language': language_code_for_text(sentence) or 'en',
            'sentence_number': sentence_number,
            'stories_id': story['stories_id'],
            'media_id': story['media_id'],
            'publish_date': story['publish_date'],
        })
        sentence_number += 1

    mark_as_processed(db=db, stories_id=story['stories_id'])

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

    for medium_key, medium in story_stack.items():

        # A feed or a story?
        if 'feeds' not in medium:
            continue

        for feed_key, feed in medium['feeds'].items():

            for story_key, story in feed['stories'].items():
                story = add_content_to_test_story(db=db, story=story, feed=feed)

                # MC_REWRITE_TO_PYTHON: remove type checker comment after rewrite to Python
                # noinspection PyTypeChecker
                story_stack[story_key] = story
                # noinspection PyTypeChecker
                story_stack[feed_key]['stories'][story_key] = story
                # noinspection PyTypeChecker
                story_stack[medium_key]['feeds'][feed_key]['stories'][story_key] = story

    return story_stack
