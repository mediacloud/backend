from mediawords.key_value_store.postgresql import PostgreSQLStore
from mediawords.key_value_store.mock_download import TestMockDownloadTestCase


class TestPostgreSQLStoreTestCase(TestMockDownloadTestCase):
    def _initialize_store(self) -> PostgreSQLStore:
        return PostgreSQLStore(table='raw_downloads')

    def _expected_path_prefix(self) -> str:
        return 'postgresql:'

    def test_key_value_store(self):
        self._test_key_value_store()
