from mediawords.key_value_store.amazon_s3 import AmazonS3Store
from mediawords.key_value_store.multiple_stores import MultipleStoresStore
from mediawords.key_value_store.postgresql import PostgreSQLStore
from .amazon_s3_credentials import (
    TestAmazonS3CredentialsTestCase,
    get_test_s3_credentials,
)
from .mock_download import TestMockDownloadTestCase

test_credentials = get_test_s3_credentials()


class TestMultipleStoresStoreTestCase(TestAmazonS3CredentialsTestCase, TestMockDownloadTestCase):
    def _initialize_store(self) -> MultipleStoresStore:
        postgresql_store = PostgreSQLStore(table='raw_downloads')

        amazon_s3_store = AmazonS3Store(
            access_key_id=test_credentials.access_key_id(),
            secret_access_key=test_credentials.secret_access_key(),
            bucket_name=test_credentials.bucket_name(),
            directory_name=test_credentials.directory_name(),
        )

        return MultipleStoresStore(
            stores_for_reading=[postgresql_store, amazon_s3_store],
            stores_for_writing=[postgresql_store, amazon_s3_store],
        )

    def _expected_path_prefix(self) -> str:
        # Object gets prefix from last store written to
        return 's3:'

    def test_key_value_store(self):
        self._test_key_value_store()
