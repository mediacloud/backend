"""Creating and finding media within topics."""

import re
import time
import typing

from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
import mediawords.util.url

log = create_logger(__name__)

# url and name length limits necessary to fit within postgres field
MAX_URL_LENGTH = 1024
MAX_NAME_LENGTH = 124

# try appending this to urls to generate a unique url for get_unique_medium_url()
URL_SPIDERED_SUFFIX = '#spider'

# names for spidered tag and tag set
SPIDERED_TAG_TAG = 'spidered'
SPIDERED_TAG_SET = 'spidered'

# retry query for new unique name to avoid race condition
_GUESS_MEDIUM_RETRIES = 5


class McTopicMediaException(Exception):
    """Exception arising from this package."""

    pass


class McTopicMediaUniqueException(McTopicMediaException):
    """Exception raised when guess_medium is unable to find a unique name or url for a new media source."""

    pass


def _normalize_url(url: str) -> str:
    """Cap max length of url and run through mediawords.util.url.normalize_url_lossy."""
    nu = mediawords.util.url.normalize_url_lossy(url)
    if nu is None:
        nu = url

    return nu[0:MAX_URL_LENGTH]


def generate_medium_url_and_name_from_url(story_url: str) -> tuple:
    """Derive the url and a media source name from a story url.

    This function just returns the pathless normalized url as the medium_url and the host nane as the medium name.

    Arguments:
    url - story url

    Returns:
    tuple in the form (medium_url, medium_name)

    """
    normalized_url = _normalize_url(story_url)

    matches = re.search(r'(http.?://([^/]+))', normalized_url, flags=re.I)
    if matches is None:
        log.warning("Unable to find host name in url: normalized_url (%s)" % story_url)
        return (story_url, story_url)

    (medium_url, medium_name) = (matches.group(1).lower(), matches.group(2).lower())

    if not medium_url.endswith('/'):
        medium_url += "/"

    return (medium_url, medium_name)


def _normalized_urls_out_of_date(db: DatabaseHandler) -> bool:
    """Return True if the media_normalized_urls table is out of date with the current normalize_url_lossy_verison().

    This function is relatively quick to run because it just compares the max media_id and db_row_last_updated
    of the media table with those of the current normalize_url_lossy_version rows in media_normalized_urls.
    """
    version = mediawords.util.url.normalize_url_lossy_version()

    max_media_id = db.query("select max(media_id) from media").flat()[0]

    max_normalized_media_id = db.query(
        "select max(media_id) from media_normalized_urls where normalize_url_lossy_version = %(a)s",
        {'a': version}).flat()[0]

    if max_media_id is None:
        return False

    if max_normalized_media_id is None:
        return True

    if max_normalized_media_id < max_media_id:
        return True

    last_media_update = db.query("select max(db_row_last_updated) from media").flat()[0]

    last_mnu_update = db.query(
        "select max(db_row_last_updated) from media_normalized_urls where normalize_url_lossy_version = %(a)s",
        {'a': version}).flat()[0]

    if last_media_update is None:
        return False

    if last_mnu_update is None:
        return True

    return last_mnu_update < last_media_update


def _update_media_normalized_urls(db: DatabaseHandler) -> None:
    """Keep media_normalized_urls table up to date.

    This function compares the media and versions in media_normalized_urls against the version returned
    by mediawords.util.url.normalize_url_lossy_version() and updates or inserts rows for any media that do not
    have up to date versions.

    """
    if not _normalized_urls_out_of_date(db):
        return

    # put a lock on this because the process of generating all media urls will take around 30 seconds, and we don't
    # want all workers to do the work
    db.begin()
    db.query("lock media_normalized_urls in access exclusive mode")

    if not _normalized_urls_out_of_date(db):
        db.commit()
        return

    log.warning("updating media_normalized_urls ...")

    version = mediawords.util.url.normalize_url_lossy_version()

    media = db.query(
        """
        select m.*
            from media m
                left join media_normalized_urls u on
                    ( m.media_id = u.media_id and u.normalize_url_lossy_version = %(a)s)
            where
                u.normalized_url is null or
                u.db_row_last_updated < m.db_row_last_updated
        """,
        {'a': version}).hashes()

    i = 0
    total = len(media)
    for medium in media:
        i += 1
        normalized_url = mediawords.util.url.normalize_url_lossy(medium['url'])
        if normalized_url is None:
            normalized_url = medium['url']

        log.info("[%d/%d] adding %s (%s)" % (i, total, medium['name'], normalized_url))

        db.query(
            "delete from media_normalized_urls where media_id = %(a)s and normalize_url_lossy_version = %(b)s",
            {'a': medium['media_id'], 'b': version})
        db.create('media_normalized_urls', {
            'media_id': medium['media_id'],
            'normalized_url': normalized_url,
            'normalize_url_lossy_version': version})

    db.commit()


def lookup_medium(db: DatabaseHandler, url: str, name: str) -> typing.Optional[dict]:
    """Lookup a media source by normalized url and then name.

    Uses mediawords.util.url.normalize_url_lossy to normalize urls.  Returns the parent media for duplicate media
    sources and returns no media that are marked foreign_rss_links.

    This function queries the media_normalized_urls table to find the matching urls.  Because the normalization
    function is in python, we have to keep that denormalized table current from within python.  This function
    is responsible for keeping the table up to date by comparing the normalize_url_lossy_version values
    in the table with the current return value of mediawords.util.url.normalize_url_lossy_version().

    Arguments:
    db - db handle
    url - url to lookup
    name - name to lookup

    Returns:
    a media source dict or None

    """
    _update_media_normalized_urls(db)

    nu = _normalize_url(url)
    version = mediawords.util.url.normalize_url_lossy_version()

    lookup_query = \
        """
        select m.*
            from media m
                join media_normalized_urls u using ( media_id )
            where
                u.normalized_url = %(a)s and
                u.normalize_url_lossy_version = %(b)s and
                foreign_rss_links = 'f'
            order by dup_media_id asc nulls last, media_id asc
        """

    medium = db.query(lookup_query, {'a': nu, 'b': version}).hash()

    if medium is None:
        medium = db.query(
            "select m.* from media m where lower(m.name) = lower(%(a)s) and m.foreign_rss_links = false",
            {'a': name}).hash()

    if medium is None:
        return None

    if medium['dup_media_id'] is not None:

        media_cycle_lookup = dict()  # type: dict
        while medium['dup_media_id'] is not None:
            if medium['media_id'] in media_cycle_lookup:
                raise McTopicMediaException('Cycle found in duplicate media path: ' + str(media_cycle_lookup.keys()))
            media_cycle_lookup[medium['media_id']] = True

            medium = db.query("select * from media where media_id = %(a)s", {'a': medium['dup_media_id']}).hash()

    if medium['foreign_rss_links']:
        raise McTopicMediaException('Parent duplicate media source %d has foreign_rss_links' % medium['media_id'])

    return medium


def get_unique_medium_name(db: DatabaseHandler, names: list) -> str:
    """Return the first name in the names list that does not yet exist for a media source, or None."""
    for name in names:
        name = name[0:MAX_NAME_LENGTH]
        name_exists = db.query("select 1 from media where lower(name) = lower(%(a)s)", {'a': name}).hash()
        if name_exists is None:
            return name

    raise McTopicMediaUniqueException("Unable to find unique name among names: " + str(names))


def get_unique_medium_url(db: DatabaseHandler, urls: list) -> str:
    """Return the first url in the list that does not yet exist for a media source, or None.

    If no unique urls are found, trying appending '#spider' to each of the urls.
    """
    spidered_urls = [u + URL_SPIDERED_SUFFIX for u in urls]
    urls = urls + spidered_urls

    for url in urls:
        url = url[0:MAX_URL_LENGTH]
        url_exists = db.query("select 1 from media where url = %(a)s", {'a': url}).hash()
        if url_exists is None:
            return url

    raise McTopicMediaUniqueException("Unable to find unique url among urls: " + str(urls))


def get_spidered_tag(db: DatabaseHandler) -> dict:
    """Return the spidered:spidered tag dict."""
    spidered_tag = db.query(
        """
        select t.*
            from tags t
                join tag_sets ts using ( tag_sets_id )
            where
                t.tag = %(a)s and
                ts.name = %(b)s
        """,
        {'a': SPIDERED_TAG_TAG, 'b': SPIDERED_TAG_SET}).hash()

    if spidered_tag is None:
        tag_set = db.find_or_create('tag_sets', {'name': SPIDERED_TAG_SET})
        spidered_tag = db.find_or_create('tags', {'tag': SPIDERED_TAG_TAG, 'tag_sets_id': tag_set['tag_sets_id']})

    return spidered_tag


def guess_medium(db: DatabaseHandler, story_url: str) -> dict:
    """Guess the media source for a story with the given url.

    The guess is based on a normalized version of the host part of the url.  The guess takes into account the
    duplicate media relationships included in the postgres database through the media.dup_media_id fields.  If
    no appropriate media source exists, this function will create a new one and return it.

    """
    (medium_url, medium_name) = generate_medium_url_and_name_from_url(story_url)

    medium = lookup_medium(db, medium_url, medium_name)

    if medium is not None:
        return medium

    normalized_medium_url = _normalize_url(medium_url)
    normalized_story_url = _normalize_url(story_url)
    all_urls = [normalized_medium_url, medium_url, normalized_story_url, story_url]

    # avoid conflicts with existing media names and urls that are missed
    # by the above query b/c of dups feeds or foreign_rss_links
    medium_name = get_unique_medium_name(db, [medium_name] + all_urls)
    medium_url = get_unique_medium_url(db, all_urls)

    # a race condition with another thread can cause this to fail sometimes, but after the medium in the
    # other process has been created, all should be fine
    for i in range(_GUESS_MEDIUM_RETRIES):
        medium = db.find_or_create('media', {'name': medium_name, 'url': medium_url, 'moderated': 't'})

        if medium is not None:
            break
        else:
            time.sleep(1)

    if medium is None:
        raise McTopicMediaUniqueException(
            "Unable to find or create medium for %s / %s" % (medium_name, medium_url))

    log.info("add medium: %s / %s / %d" % (medium_name, medium_url, medium['media_id']))

    spidered_tag = get_spidered_tag(db)

    db.find_or_create('media_tags_map', {'media_id': medium['media_id'], 'tags_id': spidered_tag['tags_id']})

    return medium
