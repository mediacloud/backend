"""Various helper functions for downloads, including storing and fetching content.

This module includes various helper function for dealing with downloads.

Most importantly, this module has the store_content and fetch_content
functions, which store and fetch content for a download from the pluggable
content store.

The storage module is configured in mediawords.yml by the
mediawords.download_storage_locations setting.

The three choices are:

* 'postgresql', which stores the content in a separate postgres table and
  optionally database
* 'amazon_s3', which stores the content in amazon_s3
* 'databaseinline', which stores the content in the downloads table downloads
  are no longer stored in `databaseinline', only read from.

The default is 'postgresql', and the production system uses Amazon S3.

This module also includes extract and related functions to handle download
extraction.
"""

import random
import re
from typing import Optional

from mediawords.db import DatabaseHandler
from mediawords.key_value_store import KeyValueStore
from mediawords.key_value_store.amazon_s3 import AmazonS3Store
from mediawords.key_value_store.cached_amazon_s3 import CachedAmazonS3Store
from mediawords.key_value_store.database_inline import DatabaseInlineStore
from mediawords.key_value_store.multiple_stores import MultipleStoresStore
from mediawords.key_value_store.postgresql import PostgreSQLStore
from mediawords.util.config import get_config
from mediawords.util.extract_text import extract_article_from_html
from mediawords.util.html import html_strip
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)

# PostgreSQL table name for storing raw downloads
RAW_DOWNLOADS_POSTGRESQL_KVS_TABLE_NAME = 'raw_downloads'

# PostgreSQL table name for storing the s3 raw downloads cache
S3_RAW_DOWNLOADS_CACHE_TABLE_NAME = 'cache.s3_raw_downloads_cache'

# Mininmum content length to extract (assuming that it has some HTML in it)
MIN_CONTENT_LENGTH_TO_EXTRACT = 4096

# If the extracted text length is less than this, try finding content in javascript variable
MIN_EXTRACTED_LENGTH_FOR_JS_EXTRACTION = 256

# these are initialized by calling the various get_*_story() functions below
_inline_store = None
_amazon_s3_store = None
_postgresql_store = None
_store_for_writing = None


class McDBIDownloadsException(Exception):
    """Default exceptions for this package."""

    pass


def reset_store_singletons() -> None:
    """Reset various store singletons, causing them to be regenerated for the next store / fetch call.

    This is mostly useful for testing.
    """
    global _inline_store
    global _amazon_s3_store
    global _postgresql_store
    global _store_for_writing

    _inline_store = None
    _amazon_s3_store = None
    _postgresql_store = None
    _store_for_writing = None


def _get_inline_store() -> KeyValueStore:
    """Get lazy initialized database inline store."""
    global _inline_store

    if _inline_store is not None:
        return _inline_store

    _inline_store = DatabaseInlineStore()

    return _inline_store


def _get_amazon_s3_store() -> KeyValueStore:
    """Get lazy initialized amazon s3 store, with credentials from mediawords.yml."""
    global _amazon_s3_store

    if _amazon_s3_store:
        return _amazon_s3_store

    config = get_config()

    if 'amazon_s3' not in config:
        raise McDBIDownloadsException("Amazon S3 download store is not configured.")

    store_params = {
        'access_key_id': config['amazon_s3']['downloads']['access_key_id'],
        'secret_access_key': config['amazon_s3']['downloads']['secret_access_key'],
        'bucket_name': config['amazon_s3']['downloads']['bucket_name'],
        'directory_name': config['amazon_s3']['downloads']['directory_name'],
    }

    if config['mediawords'].get('cache_s3_downloads', False):
        store_params['cache_table'] = S3_RAW_DOWNLOADS_CACHE_TABLE_NAME
        _amazon_s3_store = CachedAmazonS3Store(**store_params)
    else:
        _amazon_s3_store = AmazonS3Store(**store_params)

    return _amazon_s3_store


def _get_postgresql_store() -> KeyValueStore:
    """Get lazy initialized postgresql store, with credentials from mediawords.yml."""
    global _postgresql_store

    if _postgresql_store is not None:
        return _postgresql_store

    config = get_config()

    _postgresql_store = PostgreSQLStore(table=RAW_DOWNLOADS_POSTGRESQL_KVS_TABLE_NAME)

    if config['mediawords'].get('fallback_postgresql_downloads_to_s3', False):
        _postgresql_store = MultipleStoresStore(
            stores_for_reading=[_postgresql_store, _get_amazon_s3_store()],
            stores_for_writing=[_postgresql_store])

    return _postgresql_store


def _get_store_for_writing() -> KeyValueStore:
    """Get MultiStoresStore for writing downloads."""
    global _store_for_writing
    if _store_for_writing is not None:
        return _store_for_writing

    config = get_config()

    # Early sanity check on configuration
    download_storage_locations = config['mediawords'].get('download_storage_locations', [])

    if len(download_storage_locations) == 0:
        raise McDBIDownloadsException("No download stores are configured.")

    stores = []
    for location in download_storage_locations:
        location = location.lower()

        if location == 'databaseinline':
            raise McDBIDownloadsException("databaseinline location is not valid for storage")
        elif location == 'postgresql':
            store = PostgreSQLStore(table=RAW_DOWNLOADS_POSTGRESQL_KVS_TABLE_NAME)
        elif location in ('s3', 'amazon', 'amazon_s3'):
            store = _get_amazon_s3_store()
        else:
            raise McDBIDownloadsException("store location '" + location + "' is not valid")

        if store is None:
            raise McDBIDownloadsException("store location '" + location + "' is not configured")

        stores.append(store)

    _store_for_writing = MultipleStoresStore(stores_for_writing=stores)

    return _store_for_writing


def _get_store_for_reading(download: dict) -> KeyValueStore:
    """Return the store from which to read the content for the given download."""
    download = decode_object_from_bytes_if_needed(download)

    config = get_config()

    if config['mediawords'].get('read_all_downloads_from_s3', False):
        return _get_amazon_s3_store()

    path = download.get('path', 's3:')

    match = re.search('^([\w]+):', path)
    location = match.group(1) if match else 's3'
    location = location.lower()

    if location == 'content':
        download_store = _get_inline_store()
    elif location == 'postgresql':
        download_store = _get_postgresql_store()
    elif location in ('s3', 'amazon_s3'):
        download_store = _get_amazon_s3_store()
    elif location == 'gridfs' or location == 'tar':
        # these are old storage formats that we moved to postgresql
        download_store = _get_postgresql_store()
    else:
        downloads_id = download.get('downloads_id', '(no downloads_id')
        raise McDBIDownloadsException("Location 'location' is unknown for download %d", [downloads_id])

    assert download_store is not None

    return download_store


def fetch_content(db: DatabaseHandler, download: dict) -> str:
    """Fetch the content for the given download from the configured content store."""

    download = decode_object_from_bytes_if_needed(download)

    if 'downloads_id' not in download:
        raise McDBIDownloadsException("downloads_id not in download")

    if not download_successful(download):
        raise McDBIDownloadsException(
            "attempt to fetch content for unsuccessful download: %d" % (download['downloads_id']))

    store = _get_store_for_reading(download)

    content_bytes = store.fetch_content(db, download['downloads_id'], download['path'])

    content = content_bytes.decode()

    # horrible hack to fix old content that is not stored in unicode
    config = get_config()
    ascii_hack_downloads_id = config['mediawords'].get('ascii_hack_downloads_id', 0)
    if download['downloads_id'] < ascii_hack_downloads_id:
        # this matches all non-printable-ascii characters.  python re does not support POSIX character
        # classes like [[:ascii:]]
        content = re.sub(r'[^ -~]', ' ', content)

    return content


def store_content(db: DatabaseHandler, download: dict, content: str) -> dict:
    """Store the content for the download."""
    # feed_error state indicates that the download was successful but that there was a problem
    # parsing the feed afterward.  so we want to keep the feed_error state even if we redownload
    # the content

    download = decode_object_from_bytes_if_needed(download)
    content = decode_object_from_bytes_if_needed(content)

    new_state = 'success' if download['state'] != 'feed_error' else 'feed_error'

    try:
        path = _get_store_for_writing().store_content(db, download['downloads_id'], content)
        error = ''
    except Exception as ex:
        new_state = 'error'
        error = "error while trying to store download %d: %s" % (download['downloads_id'], str(ex))
        path = ''

    if new_state == 'success':
        error = ''

    db.update_by_id('downloads', download['downloads_id'], {'state': new_state, 'path': path, 'error_message': error})

    download = db.find_by_id('downloads', download['downloads_id'])

    return download


def _get_cached_extractor_results(db: DatabaseHandler, download: dict) -> Optional[dict]:
    """Get extractor results from cache.

    Return:
    None if there is a miss or a dict in the form of extract_content() if there is a hit.
    """
    download = decode_object_from_bytes_if_needed(download)

    r = db.query("""
        SELECT extracted_html, extracted_text
        FROM cached_extractor_results
        WHERE downloads_id = %(a)s
    """, {'a': download['downloads_id']}).hash()

    log.debug("EXTRACTOR CACHE HIT" if r is not None else "EXTRACTOR CACHE MISS")

    return r


def _set_cached_extractor_results(db, download: dict, results: dict) -> None:
    """Store results in extractor cache and manage size of cache."""

    # This cache is used as a backhanded way of extracting stories asynchronously in the topic spider.  Intead of
    # submitting extractor jobs and then directly checking whether a given story has been extracted, we just
    # throw extraction jobs in chunks into the extractor job and cache the results.  Then if we re-extract
    # the same story shortly after, this cache will hit and the cost will be trivial.

    download = decode_object_from_bytes_if_needed(download)
    results = decode_object_from_bytes_if_needed(results)

    max_cache_entries = 1000 * 1000

    # We only need this cache to be a few thousand rows in size for the above to work, but it is cheap
    # to have up to a million or so rows. So just randomly clear the cache every million requests or so and
    # avoid expensively keeping track of the size of the postgres table.
    if random.random() * (max_cache_entries / 10) < 1:
        db.query("""
            DELETE FROM cached_extractor_results
            WHERE cached_extractor_results_id IN (
                SELECT cached_extractor_results_id
                FROM cached_extractor_results
                ORDER BY cached_extractor_results_id DESC
                OFFSET %(a)s
            )
        """, {'a': max_cache_entries})

    cache = {
        'extracted_html': results['extracted_html'],
        'extracted_text': results['extracted_text'],
        'downloads_id': download['downloads_id']
    }

    db.create('cached_extractor_results', cache)


def extract(db: DatabaseHandler, download: dict, use_cache: bool = False) -> dict:
    """Extract the content for the given download.

    Arguments:
    db - db handle
    download - download dict from db
    use_cache - get and set results in extractor cache

    Returns:
    see extract_content() below

    """
    download = decode_object_from_bytes_if_needed(download)
    if isinstance(use_cache, bytes):
        use_cache = decode_object_from_bytes_if_needed(use_cache)
    use_cache = bool(int(use_cache))

    if use_cache:
        results = _get_cached_extractor_results(db, download)
        if results is not None:
            return results

    content = fetch_content(db, download)

    results = extract_content(content)

    if use_cache:
        _set_cached_extractor_results(db, download, results)

    return results


def _call_extractor_on_html(content: str) -> dict:
    """Call extractor on the content."""
    content = decode_object_from_bytes_if_needed(content)

    extracted_html = extract_article_from_html(content)
    extracted_text = html_strip(extracted_html)

    return {'extracted_html': extracted_html, 'extracted_text': extracted_text}


def extract_content(content: str) -> dict:
    """Extract text and html from the provided HTML content.

    Extraction means pulling the substantive text out of a web page, eliminating the navigation, ads, and other
    boilerplate content.

    Arguments:
    content - html from which to extract

    Returns:
    a dict in the form {'extracted_html': html, 'extracted_text': text}

    """
    content = decode_object_from_bytes_if_needed(content)

    # Don't run through expensive extractor if the content is short and has no html
    if len(content) < MIN_CONTENT_LENGTH_TO_EXTRACT and re.search(r'<.*>', content) is None:
        log.info("Content length is less than MIN_CONTENT_LENGTH_TO_EXTRACT and has no HTML so skipping extraction")
        ret = {'extracted_html': content, 'extracted_text': content}
    else:
        ret = _call_extractor_on_html(content)

    return ret


def download_successful(download: dict) -> bool:
    """Return true if the download was downloaded successfully.

    This method is needed because there are cases it which the download was sucessfully downloaded
    but had a subsequent processing error. e.g. 'extractor_error' and 'feed_error'
    """
    download = decode_object_from_bytes_if_needed(download)

    return download['state'] in ('success', 'feed_error', 'extractor_error')


def get_media_id(db: DatabaseHandler, download: dict) -> int:
    """Convenience method to get the media_id for the download."""
    download = decode_object_from_bytes_if_needed(download)

    return db.query("""
        SELECT media_id
        FROM feeds
        WHERE feeds_id = %(feeds_id)s
    """, {'feeds_id': download['feeds_id']}).hash()['media_id']


def get_medium(db: DatabaseHandler, download: dict) -> dict:
    """Convenience method to get the media source for the given download."""
    download = decode_object_from_bytes_if_needed(download)

    return db.query("""
        SELECT m.*
        FROM feeds AS f
            JOIN media AS m
                ON f.media_id = m.media_id
        WHERE feeds_id = %(feeds_id)s
    """, {'feeds_id': download['feeds_id']}).hash()
