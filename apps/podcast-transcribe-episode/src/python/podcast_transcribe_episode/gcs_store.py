import os
from typing import Optional

# noinspection PyPackageRequirements
from google.cloud import storage
# noinspection PyPackageRequirements
from google.cloud.exceptions import NotFound
# noinspection PyPackageRequirements
from google.cloud.storage import Blob, Bucket
# noinspection PyPackageRequirements
from google.cloud.storage.retry import DEFAULT_RETRY

from mediawords.util.log import create_logger

from .config import AbstractGCBucketConfig, GCAuthConfig
from .exceptions import McProgrammingError, McConfigurationError, McPermanentError, McTransientError

log = create_logger(__name__)

_GCS_API_RETRIES = DEFAULT_RETRY.with_delay(initial=5, maximum=60, multiplier=2).with_deadline(deadline=60 * 10)
"""Google Cloud Storage's retry policy."""

_GCS_UPLOAD_DOWNLOAD_NUM_RETRIES = 10
"""Number of retries to do when uploading / downloading."""


class GCSStore(object):
    """Google Cloud Storage store."""

    __slots__ = [
        '__bucket_internal',
        '__auth_config',
        '__bucket_config',
    ]

    def __init__(self, bucket_config: AbstractGCBucketConfig, auth_config: Optional[GCAuthConfig] = None):
        if not bucket_config:
            raise McConfigurationError("Bucket configuration is unset.")

        if not auth_config:
            auth_config = GCAuthConfig()

        self.__auth_config = auth_config
        self.__bucket_config = bucket_config
        self.__bucket_internal = None

    @property
    def _bucket(self) -> Bucket:
        """Lazy-loaded bucket."""
        if not self.__bucket_internal:

            try:
                storage_client = storage.Client.from_service_account_json(self.__auth_config.gc_auth_json_file())
                self.__bucket_internal = storage_client.get_bucket(
                    bucket_or_name=self.__bucket_config.bucket_name(),
                    retry=_GCS_API_RETRIES,
                )
            except Exception as ex:
                raise McConfigurationError(f"Unable to get GCS bucket '{self.__bucket_config.bucket_name()}': {ex}")

        return self.__bucket_internal

    @classmethod
    def _remote_path(cls, path_prefix: str, object_id: str):
        if not object_id:
            raise McProgrammingError("Object ID is unset.")

        path = os.path.join(path_prefix, object_id)

        # GCS doesn't like double slashes...
        path = os.path.normpath(path)

        # ...nor is a fan of slashes at the start of path
        while path.startswith('/'):
            path = path[1:]

        return path

    def _blob_from_object_id(self, object_id: str) -> Blob:
        if not object_id:
            raise McProgrammingError("Object ID is unset.")

        remote_path = self._remote_path(path_prefix=self.__bucket_config.path_prefix(), object_id=object_id)
        blob = self._bucket.blob(remote_path)
        return blob

    def object_exists(self, object_id: str) -> bool:
        """
        Test if object exists at remote location.

        :param object_id: Object ID that should be tested.
        :return: True if object already exists under a given object ID.
        """

        if not object_id:
            raise McProgrammingError("Object ID is unset.")

        log.debug(f"Testing if object ID {object_id} exists...")

        blob = self._blob_from_object_id(object_id=object_id)

        log.debug(f"Testing blob for existence: {blob}")

        try:
            # blob.reload() returns metadata too
            blob.reload(retry=_GCS_API_RETRIES)

        except NotFound as ex:
            log.debug(f"Object '{object_id}' was not found: {ex}")
            exists = False

        except Exception as ex:
            raise McProgrammingError(f"Unable to test whether GCS object {object_id} exists: {ex}")

        else:
            exists = True

        return exists

    def upload_object(self, local_file_path: str, object_id: str) -> None:
        """
        Upload a local file to a GCS object.

        Will overwrite existing objects with a warning.

        :param local_file_path: Local file that should be stored.
        :param object_id: Object ID under which the object should be stored.
        """

        if not os.path.isfile(local_file_path):
            raise McProgrammingError(f"Local file '{local_file_path}' does not exist.")

        if not object_id:
            raise McProgrammingError("Object ID is unset.")

        log.debug(f"Uploading '{local_file_path}' as object ID {object_id}...")

        if self.object_exists(object_id=object_id):
            log.warning(f"Object {object_id} already exists, will overwrite.")

        blob = self._blob_from_object_id(object_id=object_id)

        try:
            blob.upload_from_filename(filename=local_file_path, content_type='application/octet-stream')
        except Exception as ex:
            raise McTransientError(f"Unable to upload '{local_file_path}' as object ID {object_id}: {ex}")

    # FIXME write some tests
    def download_object(self, object_id: str, local_file_path: str) -> None:
        """
        Download a GCS object to a local file.

        :param object_id: Object ID of an object that should be downloaded.
        :param local_file_path: Local file that the object should be stored to.
        """

        if os.path.isfile(local_file_path):
            raise McProgrammingError(f"Local file '{local_file_path}' already exists.")

        if not object_id:
            raise McProgrammingError("Object ID is unset.")

        log.debug(f"Downloading object ID {object_id} to '{local_file_path}'...")

        if not self.object_exists(object_id=object_id):
            raise McPermanentError(f"Object ID {object_id} was not found.")

        blob = self._blob_from_object_id(object_id=object_id)

        try:
            blob.download_to_filename(filename=local_file_path)
        except Exception as ex:
            raise McTransientError(f"Unable to download object ID {object_id} to '{local_file_path}': {ex}")

    def delete_object(self, object_id: str) -> None:
        """
        Delete object from remote location.

        Doesn't raise if object doesn't exist.

        Used mostly for running tests, e.g. to find out what happens if the object to be fetched doesn't exist anymore.

        :param object_id: Object ID that should be deleted.
        """

        if not object_id:
            raise McProgrammingError("Object ID is unset.")

        log.debug(f"Deleting object ID {object_id}...")

        blob = self._blob_from_object_id(object_id=object_id)

        try:
            blob.delete(retry=_GCS_API_RETRIES)

        except NotFound:
            log.warning(f"Object {object_id} doesn't exist.")

        except Exception as ex:
            raise McProgrammingError(f"Unable to delete GCS object {object_id}: {ex}")

    def object_uri(self, object_id: str) -> str:
        """
        Generate Google Cloud Storage URI for the object.

        :param object_id: Object ID to return the URI for.
        :return: Full Google Cloud Storage URI of the object, e.g. "gs://<bucket_name>/<path>/<object_id>".
        """

        if not object_id:
            raise McProgrammingError("Object ID is unset.")

        uri = "gs://{host}/{remote_path}".format(
            host=self.__bucket_config.bucket_name(),
            remote_path=self._remote_path(path_prefix=self.__bucket_config.path_prefix(), object_id=object_id),
        )

        return uri
