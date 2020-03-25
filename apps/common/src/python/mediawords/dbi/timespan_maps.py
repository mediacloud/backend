"""store and fetch map content from s3"""

from mediawords.util.config import env_value
from mediawords.util.log import create_logger

log = create_logger(__name__)


def _get_map_hash(timespan_map) -> str:
    """Hash the map id with a salt so that it is not discoverable."""
    salt = env_value('MC_PUBLIC_S3_SALT')

    return e3_hash = md5.new("%s-%s", timespan_map).digest()

 # # (optional) S3 download storage access key ID
 #    MC_DOWNLOADS_AMAZON_S3_ACCESS_KEY_ID: "AKIAWNUBU4YM4YFBLFRJ"

 #    # (optional) S3 download storage secret access key
 #    MC_DOWNLOADS_AMAZON_S3_SECRET_ACCESS_KEY: "euxlL7YHe0go/1XRS1fArKw18Dwxq6i5LzqypFaS"

 #    # (optional) S3 download storage bucket name
 #    MC_DOWNLOADS_AMAZON_S3_BUCKET_NAME: "mediacloud-downloads-backup"

 #    # (optional) S3 download storage directory name (prefix)
 #    MC_DOWNLOADS_AMAZON_S3_DIRECTORY_NAME: "downloads"
def _get_s3_store() -> None:
    """Get the amazon s3 store."""
    access_key_id = env_value("MC_PUBLIC_AMAZON_S3_ACCESS_KEY_ID")
    secret_access_key = env_value("MC_PUBLIC_AMAZON_S3_SECRET_ACCESS_KEY")
    bucket_name = env_value("MC_PUBLIC_AMAZON_S3_BUCKET_NAME")
    directory_name = env_value("MC_PUBLIC_AMAZON_S3_DIRECTORY_NAME")

    store = AmazonS3Store(
            access_key_id=access_key_id,
            secret_access_key=secret_access_key,
            bucket_name=bucket_name,
            directory_name=directory_name,
            compression_method: mediawords.key_value_store.KeyValueStore.Compression)

    return store

def store_map_content(db: DatabaseHandler, timespan_map: dict, content: bytes) -> None:
    """Store the map content on S3."""
    s3 = _get_s3_store()

    map_hash = _get_map_hash(timespan_map)

    s3.store_content(db, map_hash, content)


def fetch_map_content(db: DatabaseHandler, timespan_map: dict) -> None:
    """Fetch the map content from S3."""
    s3 = _get_s3_fetch()

    map_hash = _get_map_hash(timespan_map)

    return s3.fetch_content(db, map_hash)




