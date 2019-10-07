import os
from typing import Union

import boto3
# noinspection PyPackageRequirements
from botocore.config import Config as BotoCoreConfig
# noinspection PyPackageRequirements
from botocore.exceptions import ClientError

from mediawords.db import DatabaseHandler
from mediawords.key_value_store import KeyValueStore, McKeyValueStoreException
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class McAmazonS3StoreException(McKeyValueStoreException):
    """Amazon S3 key-value store exception."""
    pass


class AmazonS3Store(KeyValueStore):
    """Amazon S3 key-value store."""

    # Default object compression method
    _DEFAULT_COMPRESSION_METHOD = KeyValueStore.Compression.GZIP

    # Should the Amazon S3 module use secure (SSL-encrypted) connections?
    __USE_SSL = True

    # How many seconds should the module wait before bailing on a request to S3 (in seconds)
    # (timeout should "fit in" at least __READ_ATTEMPTS number of retries within the time period)
    __TIMEOUT = 60

    # Check if content exists before storing (good for debugging, slows down the stores)
    __CHECK_IF_EXISTS_BEFORE_STORING = False

    # Check if content exists before fetching (good for debugging, slows down the fetches)
    __CHECK_IF_EXISTS_BEFORE_FETCHING = True

    # Check if content exists before deleting (good for debugging, slows down the deletes)
    __CHECK_IF_EXISTS_BEFORE_DELETING = False

    # S3's number of read / write attempts
    # (in case waiting 20 seconds for the read / write to happen doesn't help, the instance should retry writing a
    # couple of times)
    __READ_ATTEMPTS = 3
    __WRITE_ATTEMPTS = 3

    __slots__ = [
        '__access_key_id',
        '__secret_access_key',
        '__bucket_name',
        '__directory_name',

        '__compression_method',

        # Boto3 objects
        '__s3',

        # Process PID (to prevent forks attempting to clone the Net::Amazon::S3 accessor objects)
        '__pid',
    ]

    def __init__(self,
                 access_key_id: str,
                 secret_access_key: str,
                 bucket_name: str,
                 directory_name: str,
                 compression_method: KeyValueStore.Compression = _DEFAULT_COMPRESSION_METHOD):
        """Constructor."""

        access_key_id = decode_object_from_bytes_if_needed(access_key_id)
        secret_access_key = decode_object_from_bytes_if_needed(secret_access_key)
        bucket_name = decode_object_from_bytes_if_needed(bucket_name)
        directory_name = decode_object_from_bytes_if_needed(directory_name)

        if access_key_id is None or len(access_key_id) == 0:
            raise McAmazonS3StoreException("Access key ID is unset.")
        if secret_access_key is None or len(secret_access_key) == 0:
            raise McAmazonS3StoreException("Secret access key is unset.")
        if bucket_name is None or len(bucket_name) == 0:
            raise McAmazonS3StoreException("Bucket name is unset.")
        if directory_name is None:
            raise McAmazonS3StoreException("Directory name is None.")

        # MC_REWRITE_TO_PYTHON: remove after rewrite to Perl
        if compression_method is None or len(str(compression_method)) == 0:
            compression_method = self._DEFAULT_COMPRESSION_METHOD

        if not self._compression_method_is_valid(compression_method):
            raise McAmazonS3StoreException("Unsupported compression method: %s" % compression_method)

        if not directory_name.endswith('/'):
            directory_name = directory_name + '/'

        self.__access_key_id = access_key_id
        self.__secret_access_key = secret_access_key
        self.__bucket_name = bucket_name
        self.__directory_name = directory_name
        self.__compression_method = compression_method

        self.__pid = os.getpid()
        self.__s3 = None

    def __initialize_s3(self) -> None:
        """Initialize S3 or raise an exception."""

        if os.getpid() == self.__pid:
            if self.__s3 is not None:
                # Already initialized on the very same process
                return

        # Timeout should "fit in" at least $AMAZON_S3_READ_ATTEMPTS number of retries within the time period
        request_timeout = int((self.__TIMEOUT / self.__READ_ATTEMPTS) - 1)
        if request_timeout < 10:
            raise McAmazonS3StoreException("Amazon S3 request timeout is too small: %d" % request_timeout)

        config = BotoCoreConfig(connect_timeout=request_timeout,
                                read_timeout=request_timeout)

        try:
            self.__s3 = boto3.resource(service_name='s3',
                                       aws_access_key_id=self.__access_key_id,
                                       aws_secret_access_key=self.__secret_access_key,
                                       use_ssl=self.__USE_SSL,
                                       config=config)
        except Exception as ex:
            raise McAmazonS3StoreException("Unable to create S3 client: %s" % str(ex))

        # Verify that the bucket exists
        bucket_found = False
        for bucket in self.__s3.buckets.all():
            if bucket.name == self.__bucket_name:
                bucket_found = True
                break
        if not bucket_found:
            raise McAmazonS3StoreException("Bucket '%s' was not found." % self.__bucket_name)

        # Save PID
        self.__pid = os.getpid()

    def __s3_key_for_object_id(self, object_id: int) -> str:
        """Return S3 path for object ID."""
        return '%s%d' % (self.__directory_name, object_id,)

    # FIXME add return type
    def __object_for_object_id(self, object_id: int):
        """Return S3.Object() for object ID."""
        return self.__s3.Object(bucket_name=self.__bucket_name,
                                key=self.__s3_key_for_object_id(object_id=object_id))

    def fetch_content(self, db: DatabaseHandler, object_id: int, object_path: str = None) -> bytes:
        """Read object from Amazon S3."""

        object_id = self._prepare_object_id(object_id)

        self.__initialize_s3()

        if self.__CHECK_IF_EXISTS_BEFORE_FETCHING:
            if not self.content_exists(db=db, object_id=object_id, object_path=object_path):
                raise McAmazonS3StoreException("Object ID %d does not exist." % object_id)

        content = None

        # S3 sometimes times out when reading, so we'll try to read several times
        for retry in range(self.__READ_ATTEMPTS):

            if retry > 0:
                log.warning("Retrying (#%d)..." % retry)

            try:
                o = self.__object_for_object_id(object_id)
                o_get = o.get()
                content = o_get['Body'].read()

            except Exception as ex:
                log.error("Attempt to read object ID %d didn't succeed because: %s" % (object_id, str(ex),))

            else:
                break

        if content is None:
            raise McAmazonS3StoreException(
                "Unable to read object ID %d after %d retries." % (object_id, self.__READ_ATTEMPTS,)
            )

        if not isinstance(content, bytes):
            raise McAmazonS3StoreException("Content is not bytes for object ID %d." % object_id)

        try:
            content = self._uncompress_data_for_method(data=content, compression_method=self.__compression_method)
        except Exception as ex:
            raise McAmazonS3StoreException("Unable to uncompress data for object ID %d: %s" % (object_id, str(ex),))

        if content is None:
            raise McAmazonS3StoreException("Content is None after uncompression for object ID %d" % object_id)
        if not isinstance(content, bytes):
            raise McAmazonS3StoreException("Content is not bytes after uncompression for object ID %d" % object_id)

        return content

    def store_content(self, db: DatabaseHandler, object_id: int, content: Union[str, bytes]) -> str:
        """Write object to Amazon S3."""

        object_id = self._prepare_object_id(object_id)
        content = self._prepare_content(content)

        self.__initialize_s3()

        if self.__CHECK_IF_EXISTS_BEFORE_FETCHING:
            if not self.content_exists(db=db, object_id=object_id):
                log.info(
                    (
                        "Object ID %d already exists, will store a new version or overwrite "
                        "(depending on whether or not versioning is enabled)."
                    ) % object_id)

        try:
            content = self._compress_data_for_method(data=content, compression_method=self.__compression_method)
        except Exception as ex:
            raise McAmazonS3StoreException("Unable to compress data for object ID %d: %s" % (object_id, str(ex),))

        if content is None:
            raise McAmazonS3StoreException("Content is None after compression for object ID %d" % object_id)
        if not isinstance(content, bytes):
            raise McAmazonS3StoreException("Content is not bytes after compression for object ID %d" % object_id)

        # S3 sometimes times out when writing, so we'll try to read several times
        write_was_successful = False
        for retry in range(self.__WRITE_ATTEMPTS):

            if retry > 0:
                log.warning("Retrying (#%d)..." % retry)

            try:
                o = self.__object_for_object_id(object_id)
                o.put(Body=content)
                write_was_successful = True

            except Exception as ex:
                log.error("Attempt to write object ID %d didn't succeed because: %s" % (object_id, str(ex),))

            else:
                break

        if not write_was_successful:
            raise McAmazonS3StoreException(
                "Unable to write object ID %d after %d retries." % (object_id, self.__WRITE_ATTEMPTS,)
            )

        path = 's3:%s' % self.__s3_key_for_object_id(object_id=object_id)
        return path

    def remove_content(self, db: DatabaseHandler, object_id: int, object_path: str = None) -> None:
        """Remove object from Amazon S3."""

        object_id = self._prepare_object_id(object_id)

        self.__initialize_s3()

        if self.__CHECK_IF_EXISTS_BEFORE_DELETING:
            if not self.content_exists(db=db, object_id=object_id, object_path=object_path):
                raise McAmazonS3StoreException("Object ID %d does not exist." % object_id)

        try:
            o = self.__object_for_object_id(object_id)
            o.delete()

        except Exception as ex:
            raise McAmazonS3StoreException("Unable to delete object ID %d: %s" % (object_id, str(ex),))

    def content_exists(self, db: DatabaseHandler, object_id: int, object_path: str = None) -> bool:
        """Test if object exists in Amazon S3."""

        object_id = self._prepare_object_id(object_id)

        self.__initialize_s3()

        try:
            o = self.__object_for_object_id(object_id)
            o.load()
        except ClientError as ex:
            if ex.response['Error']['Code'] == '404':
                return False
            else:
                raise ex
        except Exception as ex:
            raise McAmazonS3StoreException("Unable to test if object ID %d exists: %s" % (object_id, str(ex),))
        else:
            return True
