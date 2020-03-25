"""Store and fetch content in public s3 store.

The public s3 store is for content that we want the pubic to be able to read directly via https.  The content
is stored using salted hashes, so it should not be possible to guess the location of a url. The content 
is also not compressed.
"""

import hashlib

from mediawords.db import DatabaseHandler
import mediawords.key_value_store
from mediawords.key_value_store.amazon_s3 import AmazonS3Store
from mediawords.util.config import env_value
from mediawords.util.log import create_logger

log = create_logger(__name__)

TIMESPAN_MAPS_TYPE = 'timespan_maps'
TOPIC_DUMPS_TYPE = 'topic_dumps'
TEST_TYPE = 'test'

def get_object_hash(object_id: int) -> int:
    """Hash the object_id with a salt so that it is not discoverable."""
    salt = env_value('MC_PUBLIC_AMAZON_S3_SALT')

    key = "%s-%d" % (salt, object_id)

    return int(hashlib.md5(key.encode('utf-8')).hexdigest(), 16)


def _get_s3_store(directory_name: str) -> None:
    """Get the amazon s3 store."""
    access_key_id = env_value("MC_PUBLIC_AMAZON_S3_ACCESS_KEY_ID")
    secret_access_key = env_value("MC_PUBLIC_AMAZON_S3_SECRET_ACCESS_KEY")
    bucket_name = env_value("MC_PUBLIC_AMAZON_S3_BUCKET_NAME")

    store = AmazonS3Store(
            access_key_id=access_key_id,
            secret_access_key=secret_access_key,
            bucket_name=bucket_name,
            directory_name=directory_name,
            compression_method=mediawords.key_value_store.KeyValueStore.Compression.NONE)

    return store

def store_content(db: DatabaseHandler, object_type: str, object_id: int, content: bytes, content_type:str) -> None:
    """Store the content on S3."""
    s3 = _get_s3_store(object_type)

    hash_id = get_object_hash(object_id)

    s3.store_content(db, hash_id, content, content_type)


def fetch_content(db: DatabaseHandler, object_type: str, object_id: int) -> None:
    """Fetch the map content from S3."""
    s3 = _get_s3_store(object_type)

    hash_id = get_object_hash(object_id)

    return s3.fetch_content(db, hash_id)


def get_content_url(object_type: str, object_id: int) -> str:
    """Return the public url for the content."""
    hash_id = get_object_hash(object_id)

    return "https://mediacloud-public.s3.amazonaws.com/%s/%d" % (object_type, hash_id);
