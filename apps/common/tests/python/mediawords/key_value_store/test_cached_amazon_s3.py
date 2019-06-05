from mediawords.key_value_store.cached_amazon_s3 import CachedAmazonS3Store
from mediawords.util.text import random_string
from .amazon_s3_credentials import (
    TestAmazonS3CredentialsTestCase,
    get_test_s3_credentials,
)

test_credentials = get_test_s3_credentials()


class TestCachedAmazonS3StoreTestCase(TestAmazonS3CredentialsTestCase):
    def _initialize_store(self) -> CachedAmazonS3Store:
        return CachedAmazonS3Store(
            access_key_id=test_credentials.access_key_id(),
            secret_access_key=test_credentials.secret_access_key(),
            bucket_name=test_credentials.bucket_name(),
            directory_name=test_credentials.directory_name() + '/' + random_string(16),
            cache_table='cache.s3_raw_downloads_cache',
        )

    def _expected_path_prefix(self) -> str:
        return 's3:'

    def test_key_value_store(self):
        self._test_key_value_store()
