import abc
from unittest import TestCase

import pytest

from mediawords.db import connect_to_db
from mediawords.key_value_store import KeyValueStore, McKeyValueStoreException


class TestKeyValueStoreTestCase(TestCase, metaclass=abc.ABCMeta):
    """Abstract test case for key-value store."""

    _TEST_OBJECT_ID = 12345
    _TEST_OBJECT_ID_NONEXISTENT = _TEST_OBJECT_ID + 1

    _TEST_CONTENT_UTF_8_STRING = 'Media Cloud - pnoןɔ ɐıpǝɯ'
    _TEST_CONTENT_UTF_8 = _TEST_CONTENT_UTF_8_STRING.encode('utf-8')
    _TEST_CONTENT_INVALID_UTF_8 = b"\xf0\x90\x28\xbc"

    __slots__ = [
        '__db',
        '__store',
    ]

    @abc.abstractmethod
    def _initialize_store(self) -> KeyValueStore:
        """Return store that should be tested."""
        raise NotImplementedError("Should be implemented by concrete subclasses.")

    def _expected_path_prefix(self) -> str:
        """Return path prefix that is expected to be returned by store_content(), e.g. "postgresql:"."""
        raise NotImplementedError("Should be implemented by concrete subclasses.")

    def store(self) -> KeyValueStore:
        return self.__store

    def setUp(self):
        super().setUp()

        self.__db = connect_to_db()

        self.__store = self._initialize_store()

    def tearDown(self):
        self.__store = None
        super().tearDown()

    def _test_key_value_store(self):
        """Test fetch_content(), store_content() content_exists(), remove_content()."""
        # FIXME if someone figures out a better way to reuse unit tests for multiple classes that are being tested,
        # feel free to update the test classes

        assert self.store().content_exists(db=self.__db,
                                           object_id=self._TEST_OBJECT_ID_NONEXISTENT,
                                           object_path='') is False

        # Nonexistent item
        with pytest.raises(McKeyValueStoreException):
            # noinspection PyTypeChecker
            self.store().fetch_content(db=self.__db, object_id=self._TEST_OBJECT_ID_NONEXISTENT, object_path='')

        # Basic test
        path = self.store().store_content(db=self.__db,
                                          object_id=self._TEST_OBJECT_ID,
                                          content=self._TEST_CONTENT_UTF_8)
        assert path is not None
        assert path.startswith(self._expected_path_prefix())

        content = self.store().fetch_content(db=self.__db,
                                             object_id=self._TEST_OBJECT_ID,
                                             object_path=path)
        assert content is not None
        assert content == self._TEST_CONTENT_UTF_8

        assert self.store().content_exists(db=self.__db,
                                           object_id=self._TEST_OBJECT_ID,
                                           object_path=path) is True

        # UTF-8 string
        self.store().store_content(db=self.__db,
                                   object_id=self._TEST_OBJECT_ID,
                                   content=self._TEST_CONTENT_UTF_8_STRING)
        content = self.store().fetch_content(db=self.__db, object_id=self._TEST_OBJECT_ID)
        assert content == self._TEST_CONTENT_UTF_8

        # Invalid UTF-8
        self.store().store_content(db=self.__db,
                                   object_id=self._TEST_OBJECT_ID,
                                   content=self._TEST_CONTENT_INVALID_UTF_8)
        content = self.store().fetch_content(db=self.__db, object_id=self._TEST_OBJECT_ID)
        assert content == self._TEST_CONTENT_INVALID_UTF_8

        self.store().remove_content(db=self.__db,
                                    object_id=self._TEST_OBJECT_ID,
                                    object_path=path)

        assert self.store().content_exists(db=self.__db, object_id=self._TEST_OBJECT_ID) is False

        # Store twice
        self.store().store_content(db=self.__db,
                                   object_id=self._TEST_OBJECT_ID,
                                   content=self._TEST_CONTENT_UTF_8)
        path = self.store().store_content(db=self.__db,
                                          object_id=self._TEST_OBJECT_ID,
                                          content=self._TEST_CONTENT_UTF_8)

        assert self.store().content_exists(db=self.__db,
                                           object_id=self._TEST_OBJECT_ID,
                                           object_path=path) is True

        self.store().remove_content(db=self.__db,
                                    object_id=self._TEST_OBJECT_ID,
                                    object_path=path)

        assert self.store().content_exists(db=self.__db,
                                           object_id=self._TEST_OBJECT_ID,
                                           object_path=path) is False

        self.store().remove_content(db=self.__db,
                                    object_id=self._TEST_OBJECT_ID,
                                    object_path=path)

        # Try fetching content that was just removed
        with pytest.raises(McKeyValueStoreException):
            # noinspection PyTypeChecker
            self.store().fetch_content(db=self.__db,
                                       object_id=self._TEST_OBJECT_ID,
                                       object_path=path)
