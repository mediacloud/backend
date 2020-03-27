"""Store and fetch content in public s3 store.

The public s3 store is for content that we want the pubic to be able to read directly via https.  The content
is stored using salted hashes, so it should not be possible to guess the location of a url. The content 
is also not compressed.
"""

import hashlib
import uuid

from mediawords.db import DatabaseHandler
import mediawords.key_value_store
from mediawords.key_value_store.amazon_s3 import AmazonS3Store
from mediawords.util.config import env_value, McConfigEnvironmentVariableUnsetException
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed


log = create_logger(__name__)

TIMESPAN_MAPS_TYPE = 'timespan_maps'
TIMESPAN_FILES_TYPE = 'timespan_files'
SNAPSHOT_FILES_TYPE = 'snapshot_files'

def get_object_hash(object_id: str) -> int:
    """Hash the object_id with a salt so that it is not discoverable."""
    salt = env_value('MC_PUBLIC_AMAZON_S3_SALT')

    key = "%s-%s" % (salt, object_id)

    return int(hashlib.md5(key.encode('utf-8')).hexdigest(), 16)


def _get_test_directory_name_from_db(db) -> str:
    """Get or generate an s3 directory name from the database.

    We want each instance of containers to use the same directory but not conflict with one another, 
    so we generate the directory name and then store it in the database.
    """
    name = 'public_s3_store_directory'

    max_stories = 100000
    has_max_stories = db.query("select 1 from stories offset %(a)s", {'a': max_stories}).hash()
    if has_max_stories:
        error = "cowardly refusing to create test directory in database with at least %d stories" % max_stories
        raise McConfigEnvironmentVariableUnsetException(error)

    directory_names = db.query(
        "select value from database_variables where name = %(a)s",
        {'a': name }).flat()

    if directory_names:
        return directory_names[0]

    db.begin();
    db.query("lock table database_variables")
    
    directory_names = db.query(
        "select value from database_variables where name = %(a)s",
        {'a': name }).flat()
    if directory_names:
        directory_name = directory_names[0]
    else:
        log.warning("generating test directory name for public s3 store")
        directory_name = "test/%d" % uuid.uuid4().int
        db.query(
            "insert into database_variables (name, value) values(%(a)s, %(b)s)",
            {'a': name, 'b': directory_name })

    db.commit()

    return directory_name


def _get_directory_name(db, object_type: str) -> str:
    """Get the directory name either from the env var or from the database."""
    # MC_PUBLIC_AMAZON_S3_DIRECTORY_NAME should be unique for production to prevent overwriting
    try:
        directory_name = env_value("MC_PUBLIC_AMAZON_S3_DIRECTORY_NAME")
    except McConfigEnvironmentVariableUnsetException:
        directory_name = _get_test_directory_name_from_db(db)

    full_path = f'{directory_name}/{object_type}'

    return full_path


def _get_s3_store(db: DatabaseHandler, object_type: str) -> None:
    """Get the amazon s3 store."""
    access_key_id = env_value("MC_PUBLIC_AMAZON_S3_ACCESS_KEY_ID")
    secret_access_key = env_value("MC_PUBLIC_AMAZON_S3_SECRET_ACCESS_KEY")
    bucket_name = env_value("MC_PUBLIC_AMAZON_S3_BUCKET_NAME")

    directory_name = _get_directory_name(db, object_type)

    store = AmazonS3Store(
            access_key_id=access_key_id,
            secret_access_key=secret_access_key,
            bucket_name=bucket_name,
            directory_name=directory_name,
            compression_method=mediawords.key_value_store.KeyValueStore.Compression.GZIP)

    return store

def store_content(db: DatabaseHandler, object_type: str, object_id: str, content: bytes, content_type: str) -> None:
    """Store the content on S3."""
    object_type = decode_object_from_bytes_if_needed(object_type)
    object_id = decode_object_from_bytes_if_needed(object_id)
    content_type = decode_object_from_bytes_if_needed(content_type)

    s3 = _get_s3_store(db, object_type)

    hash_id = get_object_hash(object_id)

    s3.store_content(db, hash_id, content, content_type, content_encoding='gzip')


def fetch_content(db: DatabaseHandler, object_type: str, object_id: str) -> None:
    """Fetch the map content from S3."""
    object_type = decode_object_from_bytes_if_needed(object_type)
    object_id = decode_object_from_bytes_if_needed(object_id)

    s3 = _get_s3_store(db, object_type)

    hash_id = get_object_hash(object_id)

    return s3.fetch_content(db, hash_id)


def get_content_url(db: DatabaseHandler, object_type: str, object_id: str) -> str:
    """Return the public url for the content."""
    object_type = decode_object_from_bytes_if_needed(object_type)
    object_id = decode_object_from_bytes_if_needed(object_id)

    hash_id = get_object_hash(object_id)
    directory_name = _get_directory_name(db, object_type)

    return "https://mediacloud-public.s3.amazonaws.com/%s/%d" % (directory_name, hash_id);
