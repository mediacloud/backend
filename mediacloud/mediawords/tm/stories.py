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
import mediawords.dbi.stories.stories
from mediawords.tm.guess_date import guess_date, GuessDateResult
import mediawords.tm.media
import mediawords.util.parse_html
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
import mediawords.util.url

log = create_logger(__name__)

# url and title length limits necessary to fit within postgres field
_MAX_URL_LENGTH = 1024
_MAX_TITLE_LENGTH = 1024

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

    Only mach the first _MAX_URL_LENGTH characters of the url / redirect_url.

    Arguments:
    db - db handle
    url - story url
    redirect_url - optional url to which the story url redirects

    Returns:
    the matched story or None

    """
    u = url[0:_MAX_URL_LENGTH]

    ru = ''
    if not ignore_redirect(db, url, redirect_url):
        ru = redirect_url[0:_MAX_URL_LENGTH] if redirect_url is not None else u

    nu = mediawords.util.url.normalize_url_lossy(u)
    nru = mediawords.util.url.normalize_url_lossy(ru)

    urls = list({u, ru, nu, nru})

    # for some reason some rare urls trigger a seq scan on the below query
    db.query("set enable_seqscan=off")

    # loo for matching stories, ignore those in foreign_rss_links media
    stories = db.query(
        """
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
        fallback_date: typing.Optional[datetime.datetime] = None) -> dict:
    """Add a new story to the database by guessing metadata using the given url and content.

    This function guesses the medium, feed, title, and date of the story from the url and content.

    Arguments:
    db - db handle
    url - story url
    content - story content
    fallback_date - fallback to this date if the date guesser fails to find a date
    """
    if len(url) < 1:
        raise McTMStoriesException("url must not be an empty string")

    url = url[0:_MAX_URL_LENGTH]

    medium = mediawords.tm.media.guess_medium(db, url)
    feed = get_spider_feed(db, medium)
    spidered_tag = mediawords.tm.media.get_spidered_tag(db)
    title = mediawords.util.parse_html.html_title(content, url, _MAX_TITLE_LENGTH)

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

    date_guess = guess_date(url, content)
    story['publish_date'] = date_guess.date if date_guess.found else fallback_date
    if story['publish_date'] is None:
        story['publish_date'] = datetime.datetime.now().isoformat()

    try:
        story = db.create('stories', story)
    except mediawords.db.exceptions.handler.McUniqueConstraintException:
        raise McTMStoriesDuplicateException("Attempt to insert duplicate story url %s" % url)
    except Exception:
        raise McTMStoriesException("Error adding story: %s" % traceback.format_exc())

    db.query(
        "insert into stories_tags_map (stories_id, tags_id) values (%(a)s, %(b)s)",
        {'a': story['stories_id'], 'b': spidered_tag['tags_id']})

    assign_date_guess_tag(db, story, date_guess, fallback_date)

    log.debug("add story: %s; %s; %s; %d" % (story['title'], story['url'], story['publish_date'], story['stories_id']))

    db.create('feeds_stories_map', {'stories_id': story['stories_id'], 'feeds_id': feed['feeds_id']})

    download = create_download_for_new_story(db, story, feed)

    mediawords.dbi.downloads.store_content(db, download, content)

    _extract_story(db, story)

    return story


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
