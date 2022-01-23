import unittest

import mediawords.db
from mediawords.test.db.create import create_test_topic, create_test_topic_stories
from topics_mine.mine import check_job_error_rate, McTopicMineError

from mediawords.util.log import create_logger
log = create_logger(__name__)

class TestCheckJobErrorRate(unittest.TestCase):

    def test_check_error_Rate(self):
        db = mediawords.db.connect_to_db()

        topic = create_test_topic(db, 'foo')

        # first call should not raise an error because there are not topic_fetch_urls
        check_job_error_rate(db, topic)

        num_tfus = 100

        for i in range(num_tfus):
            tfu = {
                'topics_id': topic['topics_id'],
                'url': str(i),
                'state': 'pending'
            }
            db.create('topic_fetch_urls', tfu)

        # still should not return an error with all pending tfus
        check_job_error_rate(db, topic)

        db.query("update topic_fetch_urls set state = 'python error' where url = '1'")

        # only one error, so still no exception
        check_job_error_rate(db, topic)

        db.query("update topic_fetch_urls set state = 'python error'")

        # now with all errors we should get an exception
        self.assertRaises(McTopicMineError, check_job_error_rate, db, topic)

        db.query("update topic_fetch_urls set state = 'pending'")

        num_stories = 100

        create_test_topic_stories(db, topic, num_stories)

        # should not return an error with no errors in topic_stories
        check_job_error_rate(db, topic)

        db.query("update topic_stories set link_mine_error = 'test error' where stories_id = 1")

        # still should not throw an exception with only one error
        check_job_error_rate(db, topic)

        db.query("update topic_stories set link_mine_error = 'test error'")

        # now throw an exception since there are too many errors
        self.assertRaises(McTopicMineError, check_job_error_rate, db, topic)
