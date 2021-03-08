import pytest

from mediawords.key_value_store import McKeyValueStoreException
from mediawords.key_value_store.database_inline import DatabaseInlineStore
from .key_value_store_tests import TestKeyValueStoreTestCase


class TestDatabaseInlineStoreTestCase(TestKeyValueStoreTestCase):
    def _initialize_store(self) -> DatabaseInlineStore:
        return DatabaseInlineStore()

    def _expected_path_prefix(self) -> str:
        return 'content:'

    def test_fetch_exists_content(self):
        # FIXME if someone figures out a better way to reuse unit tests for multiple classes that are being tested,
        # feel free to update the test classes

        assert self.store().content_exists(db=self._db,
                                           object_id=self._TEST_OBJECT_ID_NONEXISTENT,
                                           object_path='') is False

        # Nonexistent item
        with pytest.raises(McKeyValueStoreException):
            # noinspection PyTypeChecker
            self.store().fetch_content(db=self._db, object_id=self._TEST_OBJECT_ID_NONEXISTENT, object_path='')

        test_content_path = '%s%s' % (self._expected_path_prefix(), self._TEST_CONTENT_UTF_8_STRING,)
        content = self.store().fetch_content(db=self._db,
                                             object_id=self._TEST_OBJECT_ID,
                                             object_path=test_content_path)
        assert content is not None
        assert content == self._TEST_CONTENT_UTF_8

        assert self.store().content_exists(db=self._db,
                                           object_id=self._TEST_OBJECT_ID,
                                           object_path=test_content_path) is True
