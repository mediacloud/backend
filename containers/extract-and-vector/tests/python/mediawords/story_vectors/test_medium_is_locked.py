#!/usr/bin/env py.test

from mediawords.db import connect_to_db
from mediawords.story_vectors import medium_is_locked
from mediawords.story_vectors.setup_test_story_vectors import TestStoryVectors


class TestMediumIsLocked(TestStoryVectors):

    def test_medium_is_locked(self):
        media_id = self.test_medium['media_id']

        db_locked_session = connect_to_db()

        assert medium_is_locked(db=self.db, media_id=media_id) is False

        db_locked_session.query("SELECT pg_advisory_lock(%(media_id)s)", {'media_id': media_id})
        assert medium_is_locked(db=self.db, media_id=media_id) is True

        db_locked_session.query("SELECT pg_advisory_unlock(%(media_id)s)", {'media_id': media_id})
        assert medium_is_locked(db=self.db, media_id=media_id) is False

        db_locked_session.disconnect()
