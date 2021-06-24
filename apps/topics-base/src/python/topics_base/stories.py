"""Creating, matching, and otherwise manipulating stories within topics."""

import datetime
import operator
import os
import time
from typing import Optional

import furl
import re2

from extract_and_vector.dbi.stories.extractor_arguments import PyExtractorArguments
from extract_and_vector.dbi.stories.extract import extract_and_process_story

from mediawords.db import DatabaseHandler
from mediawords.dbi.downloads import create_download_for_new_story
from mediawords.dbi.downloads.store import McDBIDownloadsException, fetch_content, store_content
from mediawords.dbi.stories.stories import add_story, MAX_URL_LENGTH, MAX_TITLE_LENGTH
from mediawords.key_value_store.amazon_s3 import McAmazonS3StoreException
from mediawords.job import JobBroker
from mediawords.util.guess_date import (
    guess_date,
    GuessDateResult,
    GUESS_METHOD_TAG_SET,
    INVALID_TAG_SET,
    INVALID_TAG,
)
from mediawords.util.log import create_logger
from mediawords.util.parse_html import html_title
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.sql import sql_now
from mediawords.util.url import get_url_distinctive_domain, normalize_url_lossy

from topics_base.media import (
    generate_medium_url_and_name_from_url,
    guess_medium,
    get_spidered_tag,
)

log = create_logger(__name__)

SPIDER_FEED_NAME = 'Spider Feed'

BINARY_EXTENSIONS = 'jpg pdf doc mp3 mp4 zip png docx gif mov'.split()

# how long to wait for extractor before raising an exception
MAX_EXTRACTOR_WAIT = 600

# how many seconds to poll to make sure we can fetch stored content
STORE_CONTENT_TIMEOUT = 10


class McTMStoriesException(Exception):
    """Default exception for package."""
    pass


class McTMStoriesDuplicateException(Exception):
    """Raised when generate_story tries to insert story with a url that is not unique for a media source."""

    pass


def url_has_binary_extension(url: str) -> bool:
    """Return true if the url has a file extension that is likely to be a large binary file."""
    try:
        path = str(furl.furl(url).path)
    except Exception as ex:
        log.warning(f"Error parsing URL '{url}': {ex}")
        return False

    ext = os.path.splitext(path)[1].lower()

    # .html -> html
    ext = ext[1:]

    return ext in BINARY_EXTENSIONS


def _extract_story(db: DatabaseHandler, story: dict) -> None:
    """Process the story through the extractor."""

    if url_has_binary_extension(story['url']):
        return

    if re2.search(r'livejournal.com\/(tag|profile)', story['url'], re2.I):
        return

    extractor_args = PyExtractorArguments(use_cache=True, use_existing=True)
    extract_and_process_story(db=db, story=story, extractor_args=extractor_args)


def _get_story_with_most_sentences(db: DatabaseHandler, stories: list) -> dict:
    """Given a list of stories, return the story with the most sentences."""
    assert len(stories) > 0

    if len(stories) == 1:
        return stories[0]

    story = db.query(
        """
            select s.*
            from stories s
            where stories_id in (
                select stories_id
                from story_sentences
                where stories_id = any (%(a)s)
                group by stories_id
                order by count(*) desc
                limit 1
            )
        """,
        {'a': [s['stories_id'] for s in stories]}).hash()

    if story is not None:
        return story
    else:
        return stories[0]


def _url_domain_matches_medium(medium: dict, urls: list) -> bool:
    """Return true if the domain of any of the story urls matches the domain of the medium url."""
    medium_domain = get_url_distinctive_domain(medium['url'])

    story_domains = [get_url_distinctive_domain(u) for u in urls]

    matches = list(filter(lambda d: medium_domain == d, story_domains))

    return len(matches) > 0


def get_preferred_story(db: DatabaseHandler, stories: list) -> dict:
    """Given a set of possible story matches, find the story that is likely the best to include in the topic.

    The best story is the one that belongs to the media source that sorts first according to the following
    criteria, in descending order of importance:

    * pointed to by some dup_media_id
    * without a dup_media_id
    * url domain matches that of the story
    * lower media_id

    Within a media source, the preferred story is the one with the most sentences.

    Arguments:
    db - db handle
    url - url of matched story
    redirect_url - redirect_url of matched story
    stories - list of stories from which to choose

    Returns:
    a single preferred story

    """
    assert len(stories) > 0

    if len(stories) == 1:
        return stories[0]

    log.debug("get_preferred_story: %d stories" % len(stories))

    media = db.query(
        """
            select *,
                exists ( select 1 from media d where d.dup_media_id = m.media_id ) as is_dup_target
            from media m
            where media_id = any(%(a)s)
        """,
        {'a': [s['media_id'] for s in stories]}).hashes()

    story_urls = [s['url'] for s in stories]

    for medium in media:
        # is_dup_target defined in query above
        medium['is_dup_target'] = 0 if medium['is_dup_target'] else 1
        medium['is_not_dup_source'] = 1 if medium['dup_media_id'] else 0
        medium['matches_domain'] = 0 if _url_domain_matches_medium(medium, story_urls) else 1
        medium['stories'] = list(filter(lambda s: s['media_id'] == medium['media_id'], stories))

    sorted_media = sorted(
        media,
        key=operator.itemgetter('is_dup_target', 'is_not_dup_source', 'matches_domain', 'media_id'))

    preferred_story = _get_story_with_most_sentences(db, sorted_media[0]['stories'])

    return preferred_story


def ignore_redirect(db: DatabaseHandler, url: str, redirect_url: Optional[str]) -> bool:
    """Return true if we should ignore redirects to the target media source.

    This is usually to avoid redirects to domain resellers for previously valid and important but now dead links."""
    if redirect_url is None or url == redirect_url:
        return False

    medium_url = generate_medium_url_and_name_from_url(redirect_url)[0]

    u = normalize_url_lossy(medium_url)

    match = db.query("select 1 from topic_ignore_redirects where url = %(a)s", {'a': u}).hash()

    return match is not None


def get_story_match(db: DatabaseHandler, url: str, redirect_url: Optional[str] = None) -> Optional[dict]:
    """Search for any story within the database that matches the given url.

    Searches for any story whose guid or url matches either the url or redirect_url or the
    mediawords.util.url.normalize_url_lossy() version of either.

    If multiple stories are found, use get_preferred_story() to decide which story to return.

    Only mach the first mediawords.dbi.stories.stories.MAX_URL_LENGTH characters of the url / redirect_url.

    Arguments:
    db - db handle
    url - story url
    redirect_url - optional url to which the story url redirects

    Returns:
    the matched story or None

    """
    u = url[0:MAX_URL_LENGTH]

    ru = ''
    if not ignore_redirect(db, url, redirect_url):
        ru = redirect_url[0:MAX_URL_LENGTH] if redirect_url is not None else u

    nu = normalize_url_lossy(u)
    nru = normalize_url_lossy(ru)

    urls = list({u, ru, nu, nru})

    # for some reason some rare urls trigger a seq scan on the below query
    db.query("set enable_seqscan=off")

    # look for matching stories, ignore those in foreign_rss_links media, only get last
    # 100 to avoid hanging job trying to handle potentially thousands of matches
    stories = db.query(
        """
            with matching_stories as (
                select distinct(s.*)
                from stories s
                    join media m
                        on s.media_id = m.media_id
                where (
                        ( s.url = any( %(a)s ) )
                     or ( s.guid = any ( %(a)s ) )
                      )
                  and m.foreign_rss_links = false
            
                union
            
                select distinct(s.*)
                from stories s
                    join media m
                        on s.media_id = m.media_id
                    join story_urls su
                        on s.stories_id = su.stories_id
                where su.url = any ( %(a)s )
                  and m.foreign_rss_links = false
            )
            
            select distinct(ms.*)
            from matching_stories ms
            order by collect_date desc
            limit 100
        """,
        {'a': urls}
    ).hashes()

    db.query("set enable_seqscan=on")

    if len(stories) == 0:
        return None

    story = get_preferred_story(db, stories)

    return story


def assign_date_guess_tag(
        db: DatabaseHandler,
        story: dict,
        date_guess: GuessDateResult,
        fallback_date: Optional[str]) -> None:
    """Assign a guess method tag to the story based on the date_guess result.

    If date_guess found a result, assign a date_guess_method:guess_by_url, guess_by_tag_*, or guess_by_unknown tag.
    Otherwise if there is a fallback_date, assign date_guess_metehod:fallback_date.  Else assign
    date_invalid:date_invalid.

    Arguments:
    db - db handle
    story - story dict from db
    date_guess - GuessDateResult from guess_date() call

    Returns:
    None

    """
    if date_guess.found:
        tag_set = GUESS_METHOD_TAG_SET
        guess_method = date_guess.guess_method
        if guess_method.startswith('Extracted from url'):
            tag = 'guess_by_url'
        elif guess_method.startswith('Extracted from tag'):
            match = re2.search(r'\<(\w+)', guess_method)
            html_tag = match.group(1) if match is not None else 'unknown'
            tag = 'guess_by_tag_' + str(html_tag)
        else:
            tag = 'guess_by_unknown'
    elif fallback_date is not None:
        tag_set = GUESS_METHOD_TAG_SET
        tag = 'fallback_date'
    else:
        tag_set = INVALID_TAG_SET
        tag = INVALID_TAG

    ts = db.find_or_create('tag_sets', {'name': tag_set})
    t = db.find_or_create('tags', {'tag': tag, 'tag_sets_id': ts['tag_sets_id']})

    db.query("DELETE FROM stories_tags_map WHERE stories_id = %(a)s", {'a': story['stories_id']})
    db.query(
        "INSERT INTO stories_tags_map (stories_id, tags_id) VALUES (%(a)s, %(b)s)",
        {'a': story['stories_id'], 'b': t['tags_id']})


def get_spider_feed(db: DatabaseHandler, medium: dict) -> dict:
    """Find or create the 'Spider Feed' feed for the media source."""

    feed = db.query(
        "select * from feeds where media_id = %(a)s and name = %(b)s",
        {'a': medium['media_id'], 'b': SPIDER_FEED_NAME}).hash()

    if feed is not None:
        return feed

    return db.find_or_create('feeds', {
        'media_id': medium['media_id'],
        'url': medium['url'] + '#spiderfeed',
        'name': SPIDER_FEED_NAME,
        'active': False,
    })


def store_and_verify_content(db: DatabaseHandler, download: dict, content: str) -> None:
    """Call store content and then poll verifying that the content has been stored.

    Only return once we have verified that the content has been stored.  Raise an error after a
    timeout if the content is not found.  It seems like S3 content is not available for fetching until a small
    delay after writing it.  This function makes sure the content is there once the store operation is done.
    """
    store_content(db, download, content)

    tries = 0
    while True:
        try:
            fetch_content(db, download)
            break
        except Exception as e:
            if tries > STORE_CONTENT_TIMEOUT:
                raise e

            log.debug("story_and_verify_content: waiting to retry verification (%d) ..." % tries)
            tries += 1
            time.sleep(1)



def generate_story(
        db: DatabaseHandler,
        url: str,
        content: str,
        title: str = None,
        publish_date: str = None,
        fallback_date: Optional[str] = None) -> dict:
    """Add a new story to the database by guessing metadata using the given url and content.

    This function guesses the medium, feed, title, and date of the story from the url and content.

    If inserting the story results in a unique constraint error based on media_id and url, return
    the existing story instead.

    Arguments:
    db - db handle
    url - story url
    content - story content
    fallback_date - fallback to this date if the date guesser fails to find a date
    """
    if len(url) < 1:
        raise McTMStoriesException("url must not be an empty string")

    log.debug(f"Generating story from URL {url}...")

    url = url[0:MAX_URL_LENGTH]

    log.debug(f"Guessing medium for URL {url}...")
    medium = guess_medium(db, url)
    log.debug(f"Done guessing medium for URL {url}: {medium}")

    log.debug(f"Getting spider feed for medium {medium}...")
    feed = get_spider_feed(db, medium)
    log.debug(f"Done getting spider feed for medium {medium}: {feed}")

    log.debug(f"Getting spidered tag...")
    spidered_tag = get_spidered_tag(db)
    log.debug(f"Done getting spidered tag: {spidered_tag}")

    if title is None:
        log.debug(f"Parsing HTML title...")
        title = html_title(content, url, MAX_TITLE_LENGTH)
        log.debug(f"Done parsing HTML title: {title}")

    story = {
        'url': url,
        'guid': url,
        'media_id': medium['media_id'],
        'title': title,
        'description': ''
    }

    # postgres refuses to insert text values with the null character
    for field in ('url', 'guid', 'title'):
        story[field] = re2.sub('\x00', '', story[field])

    date_guess = None
    if publish_date is None:
        log.debug(f"Guessing date for URL {url}...")
        date_guess = guess_date(url, content)
        log.debug(f"Done guessing date for URL {url}: {date_guess}")

        story['publish_date'] = date_guess.date if date_guess.found else None
    else:
        story['publish_date'] = publish_date

    log.debug(f"Adding story {story}...")
    story = add_story(db, story, feed['feeds_id'])
    log.debug(f"Done adding story {story}")

    db.query(
        """
        INSERT INTO stories_tags_map (stories_id, tags_id)
        VALUES (%(a)s, %(b)s)
        ON CONFLICT (stories_id, tags_id) DO NOTHING
        """,
        {'a': story['stories_id'], 'b': spidered_tag['tags_id']})

    if publish_date is None:
        log.debug(f"Assigning date guess tag...")
        assign_date_guess_tag(db, story, date_guess, fallback_date)

    log.debug("add story: %s; %s; %s; %d" % (story['title'], story['url'], story['publish_date'], story['stories_id']))

    if story.get('is_new', False):
        log.debug("Story is new, creating download...")
        download = create_download_for_new_story(db, story, feed)

        log.debug("Storing story content...")
        store_and_verify_content(db, download, content)

        log.debug("Extracting story...")
        _extract_story(db, story)
        log.debug("Done extracting story")

    else:
        log.debug("Story is not new, skipping download storage and extraction")

    log.debug(f"Done generating story from URL {url}")

    return story


def add_to_topic_stories(
        db: DatabaseHandler,
        story: dict,
        topic: dict,
        link_mined: bool = False,
        valid_foreign_rss_story: bool = False,
        iteration: int = None) -> None:
    """Add story to topic_stories table.

    Query topic_stories and topic_links to find the linking story with the smallest iteration and use
    that iteration + 1 for the new topic_stories row.
    """
    if iteration is None:
        source_story = db.query(
            """
                SELECT ts.*
                FROM topic_stories AS ts
                    INNER JOIN topic_links AS tl ON
                        ts.topics_id = tl.topics_id AND
                        ts.stories_id = tl.stories_id
                WHERE
                    tl.ref_stories_id = %(a)s AND
                    tl.topics_id = %(b)s
                ORDER BY ts.iteration
                LIMIT 1
            """, {'a': story['stories_id'], 'b': topic['topics_id']}
        ).hash()

        iteration = (source_story['iteration'] + 1) if source_story else 0

    db.query(
        """
        INSERT INTO topic_stories (
            topics_id,
            stories_id,
            iteration,
            redirect_url,
            link_mined,
            valid_foreign_rss_story
        ) VALUES (%(a)s, %(b)s, %(c)s, %(d)s, %(e)s, %(f)s)
        ON CONFLICT DO NOTHING
        """,
        {
            'a': topic['topics_id'],
            'b': story['stories_id'],
            'c': iteration,
            'd': story['url'],
            'e': link_mined,
            'f': valid_foreign_rss_story
        })


def merge_foreign_rss_stories(db: DatabaseHandler, topic: dict) -> None:
    """Move all topic stories with a foreign_rss_links medium from topic_stories back to topic_seed_urls."""
    topic = decode_object_from_bytes_if_needed(topic)

    stories = db.query(
        """
        WITH topic_stories_from_topic AS (
            SELECT stories_id
            FROM topic_stories
            WHERE
                topics_id = %(topics_id)s AND
                (NOT valid_foreign_rss_story)
        )

        SELECT stories.*
        FROM stories
            INNER JOIN media ON
                stories.media_id = media.media_id AND
                media.foreign_rss_links
        WHERE stories.stories_id IN (
            SELECT stories_id
            FROM topic_stories_from_topic
        )
        """, {'topics_id': topic['topics_id']}
    ).hashes()

    for story in stories:
        download = db.query("""
            SELECT *
            FROM downloads
            WHERE stories_id = %(stories_id)s
            ORDER BY downloads_id
            LIMIT 1
        """, {'stories_id': story['stories_id']}).hash()

        content = ''
        try:
            content = fetch_content(db, download)
        except Exception as ex:
            log.warning(f"Unable to fetch content for download {download['downloads_id']}: {ex}")

        # postgres will complain if the content has a null in it
        content = content.replace('\x00', '')

        db.begin()
        db.create('topic_seed_urls', {
            'url': story['url'],
            'topics_id': topic['topics_id'],
            'source': 'merge_foreign_rss_stories',
            'content': content
        })

        db.query(
            """
            UPDATE topic_links SET
                ref_stories_id = NULL,
                link_spidered = 'f'
            WHERE
                topics_id = %(b)s AND
                ref_stories_id = %(a)s
            """,
            {'a': story['stories_id'], 'b': topic['topics_id']})

        db.query(
            """
            DELETE FROM topic_stories
            WHERE
                stories_id = %(a)s AND
                topics_id = %(b)s
            """,
            {'a': story['stories_id'], 'b': topic['topics_id']})
        db.commit()


def copy_story_to_new_medium(db: DatabaseHandler, topic: dict, old_story: dict, new_medium: dict) -> dict:
    """Copy story to new medium.

    Copy the given story, assigning the new media_id and copying over the download, extracted text, and so on.
    Return the new story.
    """

    story = {
        'url': old_story['url'],
        'media_id': new_medium['media_id'],
        'guid': old_story['guid'],
        'publish_date': old_story['publish_date'],
        'collect_date': sql_now(),
        'description': old_story['description'],
        'title': old_story['title']
    }

    story = db.create('stories', story)
    add_to_topic_stories(db=db, story=story, topic=topic, valid_foreign_rss_story=True)

    db.query(
        """
        INSERT INTO stories_tags_map (stories_id, tags_id)
            SELECT
                %(a)s,
                stm.tags_id
            FROM stories_tags_map AS stm
            WHERE stm.stories_id = %(b)s
        """,
        {'a': story['stories_id'], 'b': old_story['stories_id']})

    feed = get_spider_feed(db, new_medium)
    db.create('feeds_stories_map', {'feeds_id': feed['feeds_id'], 'stories_id': story['stories_id']})

    old_download = db.query(
        "select * from downloads where stories_id = %(a)s order by downloads_id limit 1",
        {'a': old_story['stories_id']}).hash()
    download = create_download_for_new_story(db, story, feed)

    if old_download is not None:
        try:
            content = fetch_content(db, old_download)
            download = store_content(db, download, content)
        except (McDBIDownloadsException, McAmazonS3StoreException):
            download_update = dict([(f, old_download[f]) for f in ['state', 'error_message', 'download_time']])
            db.update_by_id('downloads', download['downloads_id'], download_update)

        db.query(
            """
            insert into download_texts (downloads_id, download_text, download_text_length)
                select %(a)s, dt.download_text, dt.download_text_length
                    from download_texts dt
                    where dt.downloads_id = %(a)s
            """,
            {'a': download['downloads_id']})

    # noinspection SqlInsertValues
    db.query(
        f"""
        insert into story_sentences (stories_id, sentence_number, sentence, media_id, publish_date, language)
            select {int(story['stories_id'])} as stories_id, sentence_number, sentence, media_id, publish_date, language
                from story_sentences
                where stories_id = %(b)s
        """,
        {'b': old_story['stories_id']})

    return story


def _get_merged_iteration(db: DatabaseHandler, topic: dict, delete_story: dict, keep_story: dict) -> int:
    """Get the smaller iteration of two stories"""
    iterations = db.query(
        """
        SELECT iteration
        FROM topic_stories
        WHERE
            topics_id = %(a)s AND
            stories_id IN (%(b)s, %(c)s) AND
            iteration IS NOT NULL
        """,
        {'a': topic['topics_id'], 'b': delete_story['stories_id'], 'c': keep_story['stories_id']}).flat()

    if len(iterations) > 0:
        return min(iterations)
    else:
        return 0


def _merge_dup_story(db, topic, delete_story, keep_story):
    """Merge delete_story into keep_story.

    Make sure all links that are in delete_story are also in keep_story and make
    sure that keep_story is in topic_stories.  once done, delete delete_story from topic_stories (but not from
    stories). also change stories_id in topic_seed_urls and add a row in topic_merged_stories_map.
    """

    log.debug(
        "%s [%d] <- %s [%d]" %
        (keep_story['title'], keep_story['stories_id'], delete_story['title'], delete_story['stories_id']))

    if delete_story['stories_id'] == keep_story['stories_id']:
        log.debug("refusing to merge identical story")
        return

    topics_id = topic['topics_id']

    merged_iteration = _get_merged_iteration(db, topic, delete_story, keep_story)
    add_to_topic_stories(db=db, topic=topic, story=keep_story, link_mined=True, iteration=merged_iteration)

    use_transaction = not db.in_transaction()
    if use_transaction:
        db.begin()

    db.query(
        """
        INSERT INTO topic_links (
            topics_id,
            stories_id,
            ref_stories_id,
            url,
            redirect_url,
            link_spidered
        )
            SELECT
                topics_id,
                %(c)s,
                ref_stories_id,
                url,
                redirect_url,
                link_spidered
            FROM topic_links AS tl
            WHERE
                tl.topics_id = %(a)s AND
                tl.stories_id = %(b)s
        ON CONFLICT DO NOTHING
        """,
        {'a': topics_id, 'b': delete_story['stories_id'], 'c': keep_story['stories_id']}
    )

    db.query(
        """
        INSERT INTO topic_links (
            topics_id,
            stories_id,
            ref_stories_id,
            url,
            redirect_url,
            link_spidered
        )
            SELECT
                topics_id,
                stories_id,
                %(c)s,
                url,
                redirect_url,
                link_spidered
            FROM topic_links AS tl
            WHERE
                tl.topics_id = %(a)s AND
                tl.ref_stories_id = %(b)s
        ON CONFLICT DO NOTHING
        """,
        {'a': topics_id, 'b': delete_story['stories_id'], 'c': keep_story['stories_id']}
    )

    db.query(
        """
        DELETE FROM topic_links
        WHERE
            topics_id = %(a)s AND
            %(b)s in (stories_id, ref_stories_id)
        """,
        {'a': topics_id, 'b': delete_story['stories_id']}
    )

    db.query(
        """
        DELETE FROM topic_stories
        WHERE
            stories_id = %(a)s AND
            topics_id = %(b)s
        """,
        {'a': delete_story['stories_id'], 'b': topics_id}
    )

    db.query(
        """
        INSERT INTO topic_merged_stories_map (source_stories_id, target_stories_id)
        VALUES (%(source_stories_id)s, %(target_stories_id)s)
        """,
        {
            'source_stories_id': delete_story['stories_id'],
            'target_stories_id': keep_story['stories_id'],
        }
    )

    db.query(
        """
        UPDATE topic_seed_urls SET
            stories_id = %(b)s
        WHERE
            stories_id = %(a)s AND
            topics_id = %(c)s
        """,
        {'a': delete_story['stories_id'], 'b': keep_story['stories_id'], 'c': topic['topics_id']}
    )

    if use_transaction:
        db.commit()


def _get_deduped_medium(db: DatabaseHandler, media_id: int) -> dict:
    """Get either the referenced medium or the deduped version of the medium by recursively following dup_media_id."""
    medium = db.require_by_id('media', media_id)
    if medium['dup_media_id'] is None:
        return medium
    else:
        return _get_deduped_medium(db, medium['dup_media_id'])


def merge_dup_media_story(db, topic, story):
    """Given a story in a dup_media_id medium, look for or create a story in the medium pointed to by dup_media_id.

    Call _merge_dup_story() on the found or cloned story in the new medium.
    """

    dup_medium = _get_deduped_medium(db, story['media_id'])

    new_story = db.query(
        """
        SELECT s.*
        FROM stories s
        WHERE
            s.media_id = %(media_id)s AND
            (
                (%(url)s IN (s.url, s.guid)) OR
                (%(guid)s IN (s.url, s.guid)) OR
                (s.title = %(title)s AND date_trunc('day', s.publish_date) = %(date)s)
            )
        """,
        {
            'media_id': dup_medium['media_id'],
            'url': story['url'],
            'guid': story['guid'],
            'title': story['title'],
            'date': story['publish_date']
        }
    ).hash()

    if new_story is None:
        new_story = copy_story_to_new_medium(db, topic, story, dup_medium)

    _merge_dup_story(db, topic, story, new_story)

    return new_story


def merge_dup_media_stories(db, topic):
    """Merge all stories belonging to dup_media_id media to the dup_media_id in the current topic"""

    log.info("merge dup media stories")

    dup_media_stories = db.query(
        """
        SELECT DISTINCT s.*
        FROM snap.live_stories AS s
            INNER JOIN topic_stories AS cs ON
                s.stories_id = cs.stories_id AND
                s.topics_id = cs.topics_id
            JOIN media AS m ON
                s.media_id = m.media_id
        WHERE
            m.dup_media_id IS NOT NULL AND
            cs.topics_id = %(a)s
        """,
        {'a': topic['topics_id']}).hashes()

    if len(dup_media_stories) > 0:
        log.info("merging %d stories" % len(dup_media_stories))

    [merge_dup_media_story(db, topic, s) for s in dup_media_stories]


def copy_stories_to_topic(db: DatabaseHandler, source_topics_id: int, target_topics_id: int) -> None:
    """Copy stories from source_topics_id into seed_urls for target_topics_id."""
    message = "copy_stories_to_topic: %s -> %s [%s]" % (source_topics_id, target_topics_id, datetime.datetime.now())

    log.info("querying novel urls from source topic...")

    db.query("set work_mem = '8GB'")

    db.query(
        """
        CREATE TEMPORARY TABLE _stories AS
            SELECT DISTINCT stories_id
            FROM topic_seed_urls
            WHERE
                topics_id = %(a)s AND
                stories_id IS NOT NULL
        ;

        CREATE TEMPORARY TABLE _urls AS
            SELECT DISTINCT url
            FROM topic_seed_urls
            WHERE topics_id = %(a)s
        ;

        """,
        {'a': target_topics_id})

    # noinspection SqlResolve
    db.query(
        """
        CREATE TEMPORARY TABLE _tsu AS
            SELECT
                %(target)s AS topics_id,
                url,
                stories_id,
                %(message)s AS source
            FROM snap.live_stories AS s
            WHERE
                s.topics_id = %(source)s AND
                s.stories_id NOT IN (
                    SELECT stories_id
                    FROM _stories
                ) AND
                s.url NOT IN (
                    SELECT url
                    FROM _urls
                )
        """,
        {'target': target_topics_id, 'source': source_topics_id, 'message': message})

    # noinspection SqlResolve
    (num_inserted,) = db.query("select count(*) from _tsu").flat()

    log.info("inserting %d urls ..." % num_inserted)

    # noinspection SqlInsertValues,SqlResolve
    db.query("insert into topic_seed_urls ( topics_id, url, stories_id, source ) select * from _tsu")

    # noinspection SqlResolve
    db.query("drop table _stories; drop table _urls; drop table _tsu;")


def _merge_dup_stories(db, topic, stories):
    """Merge a list of stories into a single story, keeping the story with the most sentences."""
    log.debug("merge dup stories")

    stories_ids = [s['stories_id'] for s in stories]

    story_sentence_counts = db.query(
        """
        select stories_id, count(*) sentence_count
            from story_sentences
            where stories_id = ANY(%(a)s)
            group by stories_id
        """,
        {'a': stories_ids}).hashes()

    ssc = {}

    for s in stories:
        ssc[s['stories_id']] = 0

    for count in story_sentence_counts:
        ssc[count['stories_id']] = count['sentence_count']

    stories = sorted(stories, key=lambda x: ssc[x['stories_id']], reverse=True)

    keep_story = stories.pop(0)

    log.debug("duplicates: %s [%s %d]" % (keep_story['title'], keep_story['url'], keep_story['stories_id']))

    [_merge_dup_story(db, topic, s, keep_story) for s in stories]


def _add_missing_normalized_title_hashes(db: DatabaseHandler, topic: dict) -> None:
    """Add a normalized_title_hash field for every stories row that is missing it for the given topic."""
    db.begin()
    db.query(
        """
        DECLARE c CURSOR FOR
            SELECT stories_id
            FROM snap.live_stories
            WHERE
                topics_id = %(a)s AND
                normalized_title_hash IS NULL
        """,
        {'a': topic['topics_id']})

    log.info('adding normalized story titles ...')

    # break this up into chunks instead of doing all topic stories at once via a simple sql query because we don't
    # want to do a single giant transaction with millions of stories
    while True:
        stories_ids = db.query("fetch 100 from c").flat()
        if len(stories_ids) < 1:
            break

        db.query("""
            UPDATE stories
            SET normalized_title_hash = md5(get_normalized_title(title, media_id))::UUID
            WHERE stories_id = ANY(%(a)s)
        """, {'a': stories_ids})

    db.commit()


def _get_dup_story_groups(db: DatabaseHandler, topic: dict) -> list:
    """Return a list of duplicate story groups.

    Find all stories within a topic that have duplicate normalized titles with a given day and media_id.  Return a
    list of story lists.  Each story list is a list of stories that are duplicated os each other.
    """
    story_pairs = db.query(
        """
        SELECT
            a.stories_id AS stories_id_a,
            b.stories_id AS stories_id_b
        FROM
            snap.live_stories AS a,
            snap.live_stories AS b
        WHERE
            a.topics_id = %(a)s AND
            a.topics_id = b.topics_id AND
            a.stories_id < b.stories_id AND
            a.media_id = b.media_id AND
            a.normalized_title_hash = b.normalized_title_hash AND
            date_trunc('day', a.publish_date) = date_trunc('day', b.publish_date)
        ORDER BY
            stories_id_a,
            stories_id_b
        """,
        {'a': topic['topics_id']}).hashes()

    story_groups = {}
    ignore_stories = {}
    for story_pair in story_pairs:
        if story_pair['stories_id_b'] in ignore_stories:
            continue

        story_a = db.require_by_id('stories', story_pair['stories_id_a'])
        story_b = db.require_by_id('stories', story_pair['stories_id_b'])

        story_groups.setdefault(story_a['stories_id'], [story_a])
        story_groups[story_a['stories_id']].append(story_b)

        ignore_stories[story_b['stories_id']] = True

    return list(story_groups.values())


def find_and_merge_dup_stories(db: DatabaseHandler, topic: dict) -> None:
    """Merge duplicate stories by media source within the topic.

    This is a transitional routine that will not be necessary once the story_urls and stories.normalized_title_hash
    fields have been generated for all historical stories.
    """
    log.info("adding normalized titles ...")
    _add_missing_normalized_title_hashes(db, topic)

    log.info("finding duplicate stories ...")
    dup_story_groups = _get_dup_story_groups(db, topic)

    log.info("merging %d duplicate story groups ..." % len(dup_story_groups))
    [_merge_dup_stories(db, topic, g) for g in dup_story_groups]
