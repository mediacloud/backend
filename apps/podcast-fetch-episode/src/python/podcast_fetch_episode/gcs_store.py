import os
from typing import Optional

# noinspection PyPackageRequirements
from google.cloud import storage
# noinspection PyPackageRequirements
from google.cloud.exceptions import NotFound
# noinspection PyPackageRequirements
from google.cloud.storage import Blob, Bucket

from mediawords.util.log import create_logger

from podcast_fetch_episode.config import PodcastFetchEpisodeConfig
from podcast_fetch_episode.exceptions import (
    McPodcastGCSStoreFailureException,
    McPodcastMisconfiguredGCSException,
)

log = create_logger(__name__)


class GCSStore(object):
    """Google Cloud Storage store."""

    __slots__ = [
        '__bucket_internal',
        '__config',
    ]

    def __init__(self, config: Optional[PodcastFetchEpisodeConfig] = None):
        if not config:
            config = PodcastFetchEpisodeConfig()

        self.__config = config
        self.__bucket_internal = None

    @property
    def _bucket(self) -> Bucket:
        """Lazy-loaded bucket."""
        if not self.__bucket_internal:

            try:
                storage_client = storage.Client.from_service_account_json(
                    self.__config.gcs_application_credentials_json_path(),
                )
                self.__bucket_internal = storage_client.get_bucket(self.__config.gcs_bucket_name())
            except Exception as ex:
                raise McPodcastGCSStoreFailureException(
                    f"Unable to get GCS bucket '{self.__config.gcs_bucket_name()}': {ex}"
                )

        return self.__bucket_internal

    @classmethod
    def _remote_path(cls, path_prefix: str, object_id: str):
        if not object_id:
            raise McPodcastMisconfiguredGCSException("Object ID is unset.")

        path = os.path.join(path_prefix, object_id)

        # GCS doesn't like double slashes...
        path = os.path.normpath(path)

        # ...nor is a fan of slashes at the start of path
        while path.startswith('/'):
            path = path[1:]

        return path

    def _blob_from_object_id(self, object_id: str) -> Blob:
        if not object_id:
            raise McPodcastMisconfiguredGCSException("Object ID is unset.")

        remote_path = self._remote_path(path_prefix=self.__config.gcs_path_prefix(), object_id=object_id)
        blob = self._bucket.blob(remote_path)
        return blob

    def object_exists(self, object_id: str) -> bool:
        """
        Test if object exists at remote location.

        :param object_id: Object ID that should be tested.
        :return: True if object already exists under a given object ID.
        """

        if not object_id:
            raise McPodcastMisconfiguredGCSException("Object ID is unset.")

        log.debug(f"Testing if object ID {object_id} exists...")

        blob = self._blob_from_object_id(object_id=object_id)

        log.debug(f"Testing blob for existence: {blob}")

        try:
            # blob.reload() returns metadata too
            blob.reload()

        except NotFound as ex:
            log.warning(f"Object '{object_id}' was not found: {ex}")
            exists = False

        except Exception as ex:
            raise McPodcastGCSStoreFailureException(f"Unable to test whether GCS object {object_id} exists: {ex}")

        else:
            exists = True

        return exists

    def store_object(self, local_file_path: str, object_id: str, mime_type: Optional[str] = None) -> str:
        """
        Store a local file to a remote location.

        Will overwrite existing objects with a warning.

        :param local_file_path: Local file that should be stored.
        :param object_id: Object ID under which the object should be stored.
        :param mime_type: MIME type which, if set, will be stored as "Content-Type".
        :return: Full Google Cloud Storage URI of the object, e.g. "gs://<bucket_name>/<path>/<object_id>".
        """

        if not os.path.isfile(local_file_path):
            raise McPodcastMisconfiguredGCSException(f"Local file '{local_file_path}' does not exist.")

        if not object_id:
            raise McPodcastMisconfiguredGCSException("Object ID is unset.")

        log.debug(f"Storing file '{local_file_path}' as object ID {object_id}...")

        if self.object_exists(object_id=object_id):
            log.warning(f"Object {object_id} already exists, will overwrite.")

        blob = self._blob_from_object_id(object_id=object_id)

        blob.upload_from_filename(filename=local_file_path, content_type=mime_type)

        return self.object_uri(object_id=object_id)

    def delete_object(self, object_id: str) -> None:
        """
        Delete object from remote location.

        Doesn't raise if object doesn't exist.

        :param object_id: Object ID that should be deleted.
        """

        if not object_id:
            raise McPodcastMisconfiguredGCSException("Object ID is unset.")

        log.debug(f"Deleting object ID {object_id}...")

        blob = self._blob_from_object_id(object_id=object_id)

        try:
            blob.delete()

        except NotFound:
            log.warning(f"Object {object_id} doesn't exist.")

        except Exception as ex:
            raise McPodcastGCSStoreFailureException(f"Unable to delete GCS object {object_id}: {ex}")

    def object_uri(self, object_id: str) -> str:
        """
        Generate Google Cloud Storage URI for the object.

        :param object_id: Object ID to return the URI for.
        :return: Full Google Cloud Storage URI of the object, e.g. "gs://<bucket_name>/<path>/<object_id>".
        """

        if not object_id:
            raise McPodcastMisconfiguredGCSException("Object ID is unset.")

        uri = "gs://{host}/{remote_path}".format(
            host=self.__config.gcs_bucket_name(),
            remote_path=self._remote_path(path_prefix=self.__config.gcs_path_prefix(), object_id=object_id),
        )

        return uri
