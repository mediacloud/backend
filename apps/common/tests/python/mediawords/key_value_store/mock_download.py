import abc

from mediawords.db import DatabaseHandler
from .key_value_store_tests import TestKeyValueStoreTestCase


class TestMockDownloadTestCase(TestKeyValueStoreTestCase, metaclass=abc.ABCMeta):
    """Abstract class for test cases which require a mock download."""

    @staticmethod
    def __create_mock_download(db: DatabaseHandler, downloads_id: int):
        db.query("""
            INSERT INTO media (
                media_id,
                url,
                name
            ) VALUES (
                1 AS media_id,
                'http://' AS url,
                'Test Media' AS name
            )
        """)
        db.query("""
            INSERT INTO feeds (
                feeds_id,
                media_id,
                name,
                url
            ) VALUES (
                1 AS feeds_id,
                1 AS media_id,
                'Test Feed' AS name,
                'http://' AS url
            )
        """)
        db.query("""
            INSERT INTO stories (
                stories_id,
                media_id,
                url,
                guid,
                title,
                publish_date,
                collect_date
            ) VALUES (
                1 AS stories_id,
                1 AS media_id,
                'http://' AS url,
                'guid' AS guid,
                'Test Story' AS title,
                NOW() AS publish_date,
                NOW() AS collect_date
            )
        """)
        db.query("""
            INSERT INTO downloads (
                downloads_id,
                feeds_id,
                stories_id,
                url,
                host,
                download_time,
                type,
                state,
                path,
                priority,
                sequence
            ) VALUES (
                %(downloads_id)s AS downloads_id,
                1 AS feeds_id,
                1 AS stories_id,
                'http://' AS url,
                '' AS host,
                NOW() AS download_time,
                'content' AS type,
                'success' AS state,
                'foo' AS path,
                0 AS priority,
                0 AS sequence
            )
        """, {'downloads_id': downloads_id})

    def setUp(self):
        super().setUp()
        self.__create_mock_download(db=self._db, downloads_id=self._TEST_OBJECT_ID)
