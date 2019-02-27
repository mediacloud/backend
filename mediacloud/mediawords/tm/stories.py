"""Creating, matching, and otherwise manipulating stories within topics."""

import datetime
import furl
import operator
import os
import re2
import traceback
import typing

from mediawords.db import DatabaseHandler
import mediawords.db.exceptions.handler
import mediawords.dbi.downloads
from mediawords.dbi.stories.extractor_arguments import PyExtractorArguments
import mediawords.dbi.stories.dup
import mediawords.dbi.stories.stories
import mediawords.key_value_store.amazon_s3
from mediawords.tm.guess_date import guess_date, GuessDateResult
import mediawords.tm.media
import mediawords.util.parse_html
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
import mediawords.util.url

log = create_logger(__name__)

SPIDER_FEED_NAME = 'Spider Feed'

BINARY_EXTENSIONS = 'jpg pdf doc mp3 mp4 zip png docx'.split()


class McTMStoriesException(Exception):
    """Defaut exception for package."""

    pass


class McTMStoriesDuplicateException(Exception):
    """Raised when generate_story tries to insert story with a url that is not unique for a media source."""

    pass


def url_has_binary_extension(url: str) -> bool:
    """Return true if the url has a file extension that is likely to be a large binary file."""
    path = str(furl.furl(url).path)
    try:
        path = str(furl.furl(url).path)
    except Exception:
        log.warning("error parsing url '%s'" % url)
        return False

    ext = os.path.splitext(path)[1].lower()

    # .html -> html
    ext = ext[1:]

    log.warning("EXTENSION: '%s'" % ext)

    return ext in BINARY_EXTENSIONS


def _extract_story(db: DatabaseHandler, story: dict) -> None:
    """Process the story through the extractor."""

    if url_has_binary_extension(story['url']):
        return

    if re2.search(r'livejournal.com\/(tag|profile)', story['url'], re2.I):
        return

    extractor_args = PyExtractorArguments(use_cache=True, use_existing=True, no_dedup_sentences=False)
    mediawords.dbi.stories.stories.extract_and_process_story(db=db, story=story, extractor_args=extractor_args)


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
    medium_domain = mediawords.util.url.get_url_distinctive_domain(medium['url'])

    story_domains = [mediawords.util.url.get_url_distinctive_domain(u) for u in urls]

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


def ignore_redirect(db: DatabaseHandler, url: str, redirect_url: typing.Optional[str]) -> bool:
    """Return true if we should ignore redirects to the target media source.

    This is usually to avoid redirects to domain resellers for previously valid and important but now dead links."""
    if redirect_url is None or url == redirect_url:
        return False

    medium_url = mediawords.tm.media.generate_medium_url_and_name_from_url(redirect_url)[0]

    u = mediawords.util.url.normalize_url_lossy(medium_url)

    match = db.query("select 1 from topic_ignore_redirects where url = %(a)s", {'a': u}).hash()

    return match is not None


def get_story_match(db: DatabaseHandler, url: str, redirect_url: typing.Optional[str] = None) -> typing.Optional[dict]:
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
    u = url[0:mediawords.dbi.stories.stories.MAX_URL_LENGTH]

    ru = ''
    if not ignore_redirect(db, url, redirect_url):
        ru = redirect_url[0:mediawords.dbi.stories.stories.MAX_URL_LENGTH] if redirect_url is not None else u

    nu = mediawords.util.url.normalize_url_lossy(u)
    nru = mediawords.util.url.normalize_url_lossy(ru)

    urls = list({u, ru, nu, nru})

    # for some reason some rare urls trigger a seq scan on the below query
    db.query("set enable_seqscan=off")

    # look for matching stories, ignore those in foreign_rss_links media, only get last
    # 100 to avoid hanging job trying to handle potentially thousands of matches
    stories = db.query(
        """
with matching_stories as (
    select distinct(s.*) from stories s
            join media m on s.media_id = m.media_id
        where
            ( ( s.url = any( %(a)s ) ) or
                ( s.guid = any ( %(a)s ) ) ) and
            m.foreign_rss_links = false

    union

    select distinct(s.*) from stories s
            join media m on s.media_id = m.media_id
            join topic_seed_urls csu on s.stories_id = csu.stories_id
        where
            csu.url = any ( %(a)s ) and
            m.foreign_rss_links = false
)

select distinct(ms.*)
    from matching_stories ms
    order by collect_date desc
    limit 100
        """,
        {'a': urls}).hashes()

    db.query("set enable_seqscan=on")

    if len(stories) == 0:
        return None

    story = get_preferred_story(db, stories)

    return story


def create_download_for_new_story(db: DatabaseHandler, story: dict, feed: dict) -> dict:
    """Create and return download object in database for the new story."""

    download = {
        'feeds_id': feed['feeds_id'],
        'stories_id': story['stories_id'],
        'url': story['url'],
        'host': mediawords.util.url.get_url_host(story['url']),
        'type': 'content',
        'sequence': 1,
        'state': 'success',
        'path': 'content:pending',
        'priority': 1,
        'extracted': 'f'
    }

    download = db.create('downloads', download)

    return download


def assign_date_guess_tag(
        db: DatabaseHandler,
        story: dict,
        date_guess: GuessDateResult,
        fallback_date: typing.Optional[str]) -> None:
    """Assign a guess method tag to the story based on the date_guess result.

    If date_guess found a result, assign a date_guess_method:guess_by_url, guess_by_tag_*, or guess_by_uknown tag.
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
        tag_set = mediawords.tm.guess_date.GUESS_METHOD_TAG_SET
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
        tag_set = mediawords.tm.guess_date.GUESS_METHOD_TAG_SET
        tag = 'fallback_date'
    else:
        tag_set = mediawords.tm.guess_date.INVALID_TAG_SET
        tag = mediawords.tm.guess_date.INVALID_TAG

    ts = db.find_or_create('tag_sets', {'name': tag_set})
    t = db.find_or_create('tags', {'tag': tag, 'tag_sets_id': ts['tag_sets_id']})

    db.query("delete from stories_tags_map where stories_id = %(a)s", {'a': story['stories_id']})
    db.query(
        "insert into stories_tags_map (stories_id, tags_id) values (%(a)s, %(b)s)",
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


def generate_story(
        db: DatabaseHandler,
        url: str,
        content: str,
        title: str = None,
        publish_date: datetime.datetime = None,
        fallback_date: typing.Optional[datetime.datetime] = None) -> dict:
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

    url = url[0:mediawords.dbi.stories.stories.MAX_URL_LENGTH]

    medium = mediawords.tm.media.guess_medium(db, url)
    feed = get_spider_feed(db, medium)
    spidered_tag = mediawords.tm.media.get_spidered_tag(db)

    if title is None:
        title = mediawords.util.parse_html.html_title(content, url, mediawords.dbi.stories.stories.MAX_TITLE_LENGTH)

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

    if publish_date is None:
        date_guess = guess_date(url, content)
        story['publish_date'] = date_guess.date if date_guess.found else fallback_date
        if story['publish_date'] is None:
            story['publish_date'] = datetime.datetime.now().isoformat()
    else:
        story['publish_date'] = publish_date

    try:
        story = db.create('stories', story)
    except mediawords.db.exceptions.handler.McUniqueConstraintException:
        return mediawords.tm.stories.get_story_match(db=db, url=story['url'])
    except Exception:
        raise McTMStoriesException("Error adding story: %s" % traceback.format_exc())

    db.query(
        "insert into stories_tags_map (stories_id, tags_id) values (%(a)s, %(b)s)",
        {'a': story['stories_id'], 'b': spidered_tag['tags_id']})

    if publish_date is None:
        assign_date_guess_tag(db, story, date_guess, fallback_date)

    log.debug("add story: %s; %s; %s; %d" % (story['title'], story['url'], story['publish_date'], story['stories_id']))

    db.create('feeds_stories_map', {'stories_id': story['stories_id'], 'feeds_id': feed['feeds_id']})

    download = create_download_for_new_story(db, story, feed)

    mediawords.dbi.downloads.store_content(db, download, content)

    _extract_story(db, story)

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
            select ts.*
                from topic_stories ts
                    join topic_links tl on ( ts.stories_id = tl.stories_id and ts.topics_id = tl.topics_id )
                where
                    tl.ref_stories_id = %(a)s and
                    tl.topics_id = %(b)s
                order by ts.iteration asc
                limit 1
            """,
            {'a': story['stories_id'], 'b': topic['topics_id']}).hash()

        iteration = (source_story['iteration'] + 1) if source_story else 0

    db.query(
        """
        insert into topic_stories
            ( topics_id, stories_id, iteration, redirect_url, link_mined, valid_foreign_rss_story )
            values ( %(a)s, %(b)s, %(c)s, %(d)s, %(e)s, %(f)s )
            on conflict do nothing
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
        select s.*
            from stories s, topic_stories ts, media m
            where
                s.stories_id = ts.stories_id and
                s.media_id = m.media_id and
                m.foreign_rss_links = true and
                ts.topics_id = %(a)s and
                not ts.valid_foreign_rss_story
        """,
        {'a': topic['topics_id']}).hashes()

    for story in stories:
        download = db.query(
            "select * from downloads where stories_id = %(a)s order by downloads_id limit 1",
            {'a': story['stories_id']}).hash()

        content = ''
        try:
            content = mediawords.dbi.downloads.fetch_content(db, download)
        except Exception:
            pass

        db.begin()
        db.create('topic_seed_urls', {
            'url': story['url'],
            'topics_id': topic['topics_id'],
            'source': 'merge_foreign_rss_stories',
            'content': content
        })

        db.query(
            "delete from topic_stories where stories_id = %(a)s and topics_id = %(b)s",
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
        'collect_date': mediawords.util.sql.sql_now(),
        'description': old_story['description'],
        'title': old_story['title']
    }

    story = db.create('stories', story)
    add_to_topic_stories(db=db, story=story, topic=topic, valid_foreign_rss_story=True)

    db.query(
        """
        insert into stories_tags_map (stories_id, tags_id)
            select %(a)s, stm.tags_id from stories_tags_map stm where stm.stories_id = %(b)s
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
            content = mediawords.dbi.downloads.fetch_content(db, old_download)
            download = mediawords.dbi.downloads.store_content(db, download, content)
        except (mediawords.dbi.downloads.McDBIDownloadsException,
                mediawords.key_value_store.amazon_s3.McAmazonS3StoreException):
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

    db.query(
        """
        insert into story_sentences (stories_id, sentence_number, sentence, media_id, publish_date, language)
            select %(a)s, sentence_number, sentence, media_id, publish_date, language
                from story_sentences
                where stories_id = %(b)s
        """,
        {'a': story['stories_id'], 'b': old_story['stories_id']})

    return story


def _get_merged_iteration(db: DatabaseHandler, topic: dict, delete_story: dict, keep_story: dict) -> int:
    """Get the smaller iteration of two stories"""
    iterations = db.query(
        """
        select iteration
            from topic_stories
            where
                topics_id = %(a)s and
                stories_id in (%(b)s, %(c)s) and
                iteration is not null
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
        insert into topic_links ( topics_id, stories_id, ref_stories_id, url, redirect_url, link_spidered )
            select topics_id, %(c)s, ref_stories_id, url, redirect_url, link_spidered
                from topic_links tl
                where
                    tl.topics_id = %(a)s and
                    tl.stories_id = %(b)s
            on conflict do nothing
        """,
        {'a': topics_id, 'b': delete_story['stories_id'], 'c': keep_story['stories_id']})

    db.query(
        """
        insert into topic_links ( topics_id, stories_id, ref_stories_id, url, redirect_url, link_spidered )
            select topics_id, stories_id, %(c)s, url, redirect_url, link_spidered
                from topic_links tl
                where
                    tl.topics_id = %(a)s and
                    tl.ref_stories_id = %(b)s
            on conflict do nothing
        """,
        {'a': topics_id, 'b': delete_story['stories_id'], 'c': keep_story['stories_id']})

    db.query(
        "delete from topic_links where topics_id = %(a)s and %(b)s in ( stories_id, ref_stories_id )",
        {'a': topics_id, 'b': delete_story['stories_id']})

    db.query(
        "delete from topic_stories where stories_id = %(a)s and topics_id = %(b)s",
        {'a': delete_story['stories_id'], 'b': topics_id})

    db.query(
        "insert into topic_merged_stories_map (source_stories_id, target_stories_id) values (%(a)s, %(b)s)",
        {'a': delete_story['stories_id'], 'b': keep_story['stories_id']})

    db.query(
        "update topic_seed_urls set stories_id = %(b)s where stories_id = %(a)s and topics_id = %(c)s",
        {'a': delete_story['stories_id'], 'b': keep_story['stories_id'], 'c': topic['topics_id']})

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
        SELECT s.* FROM stories s
            WHERE s.media_id = %(media_id)s and
                (( %(url)s in ( s.url, s.guid ) ) or
                 ( %(guid)s in ( s.url, s.guid) ) or
                 ( s.title = %(title)s and date_trunc( 'day', s.publish_date ) = %(date)s ) )
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
        SELECT distinct s.*
            FROM snap.live_stories s
                join topic_stories cs on (s.stories_id = cs.stories_id and s.topics_id = cs.topics_id)
                join media m on (s.media_id = m.media_id)
            WHERE
                m.dup_media_id is not null and
                cs.topics_id = %(a)s
        """,
        {'a': topic['topics_id']}).hashes()

    if len(dup_media_stories) > 0:
        log.info("merging %d stories" % len(dup_media_stories))

    [merge_dup_media_story(db, topic, s) for s in dup_media_stories]


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


def _get_topic_stories_by_medium(db: DatabaseHandler, topic: dict) -> dict:
    """Return hash of { $media_id: stories } for the topic."""

    stories = db.query(
        """
        select s.stories_id, s.media_id, s.title, s.url, s.publish_date
            from snap.live_stories s
            where s.topics_id = %(a)s
        """,
        {'a': topic['topics_id']}).hashes()

    media_lookup = {}
    for s in stories:
        media_lookup.setdefault(s['media_id'], [])
        media_lookup[s['media_id']].append(s)

    return media_lookup


def find_and_merge_dup_stories(db: DatabaseHandler, topic: dict) -> None:
    """Merge duplicate stories ithin each media source by url and title."""
    log.info("find and merge dup stories")

    for get_dup_stories in (
        ['url', mediawords.dbi.stories.dup.get_medium_dup_stories_by_url],
        ['title', mediawords.dbi.stories.dup.get_medium_dup_stories_by_title]
    ):

        f_name = get_dup_stories[0]
        f = get_dup_stories[1]

        # regenerate story list each time to capture previously merged stories
        media_lookup = _get_topic_stories_by_medium(db, topic)

        num_media = len(media_lookup.keys())

        for i, (media_id, stories) in enumerate(media_lookup.items()):
            if (i % 1000) == 0:
                log.info("merging dup stories by %s: media [%d / %d]" % (f_name, i, num_media))
            dup_stories = f(stories)
            [_merge_dup_stories(db, topic, s) for s in dup_stories]


def copy_stories_to_topic(db: DatabaseHandler, source_topics_id: int, target_topics_id: int) -> None:
    """Copy stories from source_topics_id into seed_urls for target_topics_id."""
    message = "copy_stories_to_topic: %s -> %s [%s]" % (source_topics_id, target_topics_id, datetime.datetime.now())

    db.query(
        """
        insert into topic_seed_urls ( topics_id, url, stories_id, source )
            select %(target)s, url, stories_id, %(message)s
                from snap.live_stories s
                where
                    s.topics_id = %(source)s and
                    s.stories_id not in ( select stories_id from topic_seed_urls where topics_id = %(target)s ) and
                    s.url not in ( select url from topic_seed_urls where topics_id = %(target)s )
        """,
        {'target': target_topics_id, 'source': source_topics_id, 'message': message})
