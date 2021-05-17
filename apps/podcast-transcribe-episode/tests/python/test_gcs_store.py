import filecmp
import os
import tempfile
from unittest import TestCase

# noinspection PyPackageRequirements
import pytest

from mediawords.workflow.exceptions import McProgrammingError, McPermanentError

from podcast_transcribe_episode.config import RawEnclosuresGCBucketConfig
from podcast_transcribe_episode.gcs_store import GCSStore

from .random_gcs_prefix import random_gcs_path_prefix


class _RandomPrefixBucketConfig(RawEnclosuresGCBucketConfig):
    """Bucket with random path prefix."""

    def __init__(self):
        super().__init__(path_prefix=random_gcs_path_prefix())


class TestGCSStore(TestCase):

    def test_remote_path(self):
        # Empty object ID
        with pytest.raises(McProgrammingError):
            GCSStore._remote_path(path_prefix='', object_id='')

        assert GCSStore._remote_path(path_prefix='', object_id='a') == 'a'
        assert GCSStore._remote_path(path_prefix='', object_id='/a') == 'a'
        assert GCSStore._remote_path(path_prefix='/', object_id='a') == 'a'
        assert GCSStore._remote_path(path_prefix='/', object_id='/a') == 'a'

        # GCS doesn't like double slashes
        assert GCSStore._remote_path(path_prefix='//', object_id='a') == 'a'
        assert GCSStore._remote_path(path_prefix='//', object_id='/a') == 'a'
        assert GCSStore._remote_path(path_prefix='//', object_id='//a') == 'a'
        assert GCSStore._remote_path(path_prefix='//', object_id='//a') == 'a'

        assert GCSStore._remote_path(path_prefix='//', object_id='//a///b//c') == 'a/b/c'

        assert GCSStore._remote_path(path_prefix='//', object_id='//a///b//../b/c') == 'a/b/c'

    def test_store_exists_delete(self):
        config = _RandomPrefixBucketConfig()
        gcs = GCSStore(bucket_config=config)

        object_id = 'test'
        assert gcs.object_exists(object_id=object_id) is False

        mock_data = os.urandom(1024 * 10)
        src_file = os.path.join(tempfile.mkdtemp('test'), 'src')
        with open(src_file, mode='wb') as f:
            f.write(mock_data)

        gcs.upload_object(local_file_path=src_file, object_id=object_id)
        assert gcs.object_exists(object_id=object_id) is True

        # Try storing twice
        gcs.upload_object(local_file_path=src_file, object_id=object_id)
        assert gcs.object_exists(object_id=object_id) is True

        dst_file = os.path.join(tempfile.mkdtemp('test'), 'dst')
        gcs.download_object(object_id=object_id, local_file_path=dst_file)
        assert os.path.isfile(dst_file)
        assert filecmp.cmp(src_file, dst_file, shallow=False)

        # Try downloading nonexistent file
        with pytest.raises(McPermanentError):
            gcs.download_object(object_id='999999', local_file_path=os.path.join(tempfile.mkdtemp('test'), 'foo'))

        gcs.delete_object(object_id=object_id)
        assert gcs.object_exists(object_id=object_id) is False

        # Try deleting nonexistent object
        gcs.delete_object(object_id='does_not_exist')
