from mediawords.db import connect_to_db
from mediawords.story_vectors import medium_is_locked
from mediawords.test.db import create_test_medium, create_test_feed, create_download_for_feed, create_test_story
from mediawords.test.test_database import TestDatabaseWithSchemaTestCase


class TestStoryVectors(TestDatabaseWithSchemaTestCase):

    def setUp(self) -> None:
        super().setUp()

        self.test_medium = create_test_medium(self.db(), 'downloads test')
        self.test_feed = create_test_feed(self.db(), 'downloads test', self.test_medium)
        self.test_download = create_download_for_feed(self.db(), self.test_feed)
        self.test_story = create_test_story(self.db(), label='downloads est', feed=self.test_feed)

        self.test_download['path'] = 'postgresql:foo'
        self.test_download['state'] = 'success'
        self.test_download['stories_id'] = self.test_story['stories_id']
        self.db().update_by_id('downloads', self.test_download['downloads_id'], self.test_download)

    def test_medium_is_locked(self):
        media_id = self.test_medium['media_id']

        db_locked_session = connect_to_db(label=self.TEST_DB_LABEL)

        assert medium_is_locked(db=self.db(), media_id=media_id) is False

        db_locked_session.query("SELECT pg_advisory_lock(%(media_id)s)", {'media_id': media_id})
        assert medium_is_locked(db=self.db(), media_id=media_id) is True

        db_locked_session.query("SELECT pg_advisory_unlock(%(media_id)s)", {'media_id': media_id})
        assert medium_is_locked(db=self.db(), media_id=media_id) is False

        db_locked_session.disconnect()
