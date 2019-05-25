"""Helper functions for storing and fetching downloads.

The storage module is 'download_storage_locations' setting.

The three choices are:

* 'postgresql', which stores the content in a separate postgres table and
  optionally database
* 'amazon_s3', which stores the content in amazon_s3
* 'databaseinline', which stores the content in the downloads table downloads
  are no longer stored in `databaseinline', only read from.

The default is 'postgresql', and the production system uses Amazon S3.
"""
import re
from typing import Optional

from mediawords.db import DatabaseHandler
from mediawords.key_value_store import KeyValueStore
from mediawords.key_value_store.amazon_s3 import AmazonS3Store
from mediawords.key_value_store.cached_amazon_s3 import CachedAmazonS3Store
from mediawords.key_value_store.database_inline import DatabaseInlineStore
from mediawords.key_value_store.multiple_stores import MultipleStoresStore
from mediawords.key_value_store.postgresql import PostgreSQLStore
from mediawords.util.config.common import CommonConfig, AmazonS3DownloadsConfig, DownloadStorageConfig
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)

# PostgreSQL table name for storing raw downloads
RAW_DOWNLOADS_POSTGRESQL_KVS_TABLE_NAME = 'raw_downloads'

# PostgreSQL table name for storing the s3 raw downloads cache
S3_RAW_DOWNLOADS_CACHE_TABLE_NAME = 'cache.s3_raw_downloads_cache'

# these are initialized by calling the various get_*_story() functions below
_inline_store = None
_amazon_s3_store = None
_postgresql_store = None
_store_for_writing = None


class McDBIDownloadsException(Exception):
    """Default exceptions for this package."""
    pass


def _default_download_storage_config() -> DownloadStorageConfig:
    return CommonConfig.download_storage()


def _default_amazon_s3_downloads_config() -> AmazonS3DownloadsConfig:
    return CommonConfig.amazon_s3_downloads()


def _get_inline_store() -> KeyValueStore:
    """Get lazy initialized database inline store."""
    global _inline_store

    if _inline_store is not None:
        return _inline_store

    _inline_store = DatabaseInlineStore()

    return _inline_store


def _get_amazon_s3_store(
        amazon_s3_downloads_config: AmazonS3DownloadsConfig,
        download_storage_config: DownloadStorageConfig,
) -> KeyValueStore:
    """Get lazy initialized amazon s3 store, with credentials from mediawords.yml."""
    global _amazon_s3_store

    if _amazon_s3_store:
        return _amazon_s3_store

    if not amazon_s3_downloads_config.access_key_id():
        raise McDBIDownloadsException("Amazon S3 download store is not configured.")

    store_params = {
        'access_key_id': amazon_s3_downloads_config.access_key_id(),
        'secret_access_key': amazon_s3_downloads_config.secret_access_key(),
        'bucket_name': amazon_s3_downloads_config.bucket_name(),
        'directory_name': amazon_s3_downloads_config.directory_name(),
    }

    if download_storage_config.cache_s3():
        store_params['cache_table'] = S3_RAW_DOWNLOADS_CACHE_TABLE_NAME
        _amazon_s3_store = CachedAmazonS3Store(**store_params)
    else:
        _amazon_s3_store = AmazonS3Store(**store_params)

    return _amazon_s3_store


def _get_postgresql_store(
        amazon_s3_downloads_config: AmazonS3DownloadsConfig,
        download_storage_config: DownloadStorageConfig,
) -> KeyValueStore:
    """Get lazy initialized postgresql store, with credentials from mediawords.yml."""
    global _postgresql_store

    if _postgresql_store is not None:
        return _postgresql_store

    _postgresql_store = PostgreSQLStore(table=RAW_DOWNLOADS_POSTGRESQL_KVS_TABLE_NAME)

    if download_storage_config.fallback_postgresql_to_s3():
        _postgresql_store = MultipleStoresStore(
            stores_for_reading=[
                _postgresql_store,
                _get_amazon_s3_store(
                    amazon_s3_downloads_config=amazon_s3_downloads_config,
                    download_storage_config=download_storage_config,
                ),
            ],
            stores_for_writing=[
                _postgresql_store,
            ])

    return _postgresql_store


def _get_store_for_writing(
        amazon_s3_downloads_config: AmazonS3DownloadsConfig,
        download_storage_config: DownloadStorageConfig,
) -> KeyValueStore:
    """Get MultiStoresStore for writing downloads."""
    global _store_for_writing
    if _store_for_writing is not None:
        return _store_for_writing

    # Early sanity check on configuration
    download_storage_locations = download_storage_config.storage_locations()

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
            store = _get_amazon_s3_store(
                amazon_s3_downloads_config=amazon_s3_downloads_config,
                download_storage_config=download_storage_config,
            )
        else:
            raise McDBIDownloadsException("store location '" + location + "' is not valid")

        if store is None:
            raise McDBIDownloadsException("store location '" + location + "' is not configured")

        stores.append(store)

    _store_for_writing = MultipleStoresStore(stores_for_writing=stores)

    return _store_for_writing


def _get_store_for_reading(
        download: dict,
        amazon_s3_downloads_config: AmazonS3DownloadsConfig,
        download_storage_config: DownloadStorageConfig,
) -> KeyValueStore:
    """Return the store from which to read the content for the given download."""
    download = decode_object_from_bytes_if_needed(download)

    if download_storage_config.read_all_from_s3():
        return _get_amazon_s3_store(
            amazon_s3_downloads_config=amazon_s3_downloads_config,
            download_storage_config=download_storage_config,
        )

    path = download.get('path', 's3:')

    match = re.search(r'^([\w]+):', path)
    location = match.group(1) if match else 's3'
    location = location.lower()

    if location == 'content':
        download_store = _get_inline_store()
    elif location == 'postgresql':
        download_store = _get_postgresql_store(
            amazon_s3_downloads_config=amazon_s3_downloads_config,
            download_storage_config=download_storage_config,
        )
    elif location in ('s3', 'amazon_s3'):
        download_store = _get_amazon_s3_store(
            amazon_s3_downloads_config=amazon_s3_downloads_config,
            download_storage_config=download_storage_config,
        )
    elif location == 'gridfs' or location == 'tar':
        # these are old storage formats that we moved to postgresql
        download_store = _get_postgresql_store(
            amazon_s3_downloads_config=amazon_s3_downloads_config,
            download_storage_config=download_storage_config,
        )
    else:
        downloads_id = download.get('downloads_id', '(no downloads_id')
        raise McDBIDownloadsException("Location 'location' is unknown for download %d", [downloads_id])

    assert download_store is not None

    return download_store


def fetch_content(
        db: DatabaseHandler,
        download: dict,
        amazon_s3_downloads_config: AmazonS3DownloadsConfig = None,
        download_storage_config: DownloadStorageConfig = None,
) -> str:
    """Fetch the content for the given download from the configured content store."""

    download = decode_object_from_bytes_if_needed(download)

    if 'downloads_id' not in download:
        raise McDBIDownloadsException("downloads_id not in download")

    if not download_successful(download):
        raise McDBIDownloadsException(
            "attempt to fetch content for unsuccessful download: %d" % (download['downloads_id']))

    if not amazon_s3_downloads_config:
        amazon_s3_downloads_config = _default_amazon_s3_downloads_config()
    if not download_storage_config:
        download_storage_config = _default_download_storage_config()

    store = _get_store_for_reading(
        download=download,
        amazon_s3_downloads_config=amazon_s3_downloads_config,
        download_storage_config=download_storage_config,
    )

    content_bytes = store.fetch_content(db, download['downloads_id'], download['path'])

    content = content_bytes.decode()

    return content


def store_content(
        db: DatabaseHandler,
        download: dict,
        content: str,
        amazon_s3_downloads_config: AmazonS3DownloadsConfig = None,
        download_storage_config: DownloadStorageConfig = None,
) -> dict:
    """Store the content for the download."""
    # feed_error state indicates that the download was successful but that there was a problem
    # parsing the feed afterward.  so we want to keep the feed_error state even if we redownload
    # the content

    download = decode_object_from_bytes_if_needed(download)
    content = decode_object_from_bytes_if_needed(content)

    if not amazon_s3_downloads_config:
        amazon_s3_downloads_config = _default_amazon_s3_downloads_config()
    if not download_storage_config:
        download_storage_config = _default_download_storage_config()

    new_state = 'success' if download['state'] != 'feed_error' else 'feed_error'

    try:
        store = _get_store_for_writing(
            amazon_s3_downloads_config=amazon_s3_downloads_config,
            download_storage_config=download_storage_config,
        )
        path = store.store_content(db, download['downloads_id'], content)
    except Exception as ex:
        raise McDBIDownloadsException("error while trying to store download %d: %s" % (download['downloads_id'], ex))

    if new_state == 'success':
        download['error_message'] = ''

    db.update_by_id(
        table='downloads',
        object_id=download['downloads_id'],
        update_hash={'state': new_state, 'path': path, 'error_message': download['error_message']},
    )

    download = db.find_by_id('downloads', download['downloads_id'])

    return download


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


def _get_first_download(db: DatabaseHandler, story: dict) -> dict:
    """Get the first download linking to this story."""

    story = decode_object_from_bytes_if_needed(story)

    first_download = db.query("""
        SELECT *
        FROM downloads
        WHERE stories_id = %(stories_id)s
        ORDER BY sequence ASC
        LIMIT 1
    """, {'stories_id': story['stories_id']}).hash()

    # MC_REWRITE_TO_PYTHON: Perlism
    if first_download is None:
        first_download = {}

    return first_download


def get_content_for_first_download(db: DatabaseHandler, story: dict) -> Optional[str]:
    """Call fetch_content on the result of _get_first_download(). Return None if the download's state is not null."""

    story = decode_object_from_bytes_if_needed(story)

    first_download = _get_first_download(db=db, story=story)

    if first_download.get('state', None) != 'success':
        log.debug("First download's state is not 'success' for story {}".format(story['stories_id']))
        return None

    content = fetch_content(db=db, download=first_download)

    return content
