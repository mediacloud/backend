from unittest import TestCase

import pytest

from mediawords.db import connect_to_db
from mediawords.solr import (
    get_solr_num_found,
    search_solr_for_processed_stories_ids,
    search_solr_for_stories_ids,
    query_solr,
    McQuerySolrRangeQueryException,
)
from mediawords.test.solr import create_indexed_test_story_stack, assert_story_query


class TestSolr(TestCase):
    DB = None
    MEDIA = None
    TEST_STORIES = None

    @classmethod
    def setUpClass(cls) -> None:
        cls.DB = connect_to_db()
        cls.MEDIA = create_indexed_test_story_stack(
            db=cls.DB,
            data={
                'medium_1': {'feed_1': [f"story_{_}" for _ in range(1, 15 + 1)]},
                'medium_2': {'feed_2': [f"story_{_}" for _ in range(16, 25 + 1)]},
                'medium_3': {'feed_3': [f"story_{_}" for _ in range(26, 50 + 1)]},
            },
        )
        cls.TEST_STORIES = cls.DB.query("SELECT * FROM stories ORDER BY md5(stories_id::text)").hashes()

    def test_basic(self):
        """Basic query."""
        story = self.TEST_STORIES.pop()
        assert_story_query(db=self.DB, q='*:*', expected_story=story, label='Simple story')

    def test_get_solr_num_found(self):
        """get_solr_num_found()."""
        expected_num_stories = self.DB.query("SELECT COUNT(*) FROM stories").flat()[0]
        got_num_stories = get_solr_num_found(db=self.DB, params={'q': '*:*'})
        assert expected_num_stories == got_num_stories, 'get_solr_num_found()'

    def test_search_solr_for_processed_stories_ids(self):
        """search_solr_for_processed_stories_ids()."""
        first_story = self.DB.query("""
            SELECT *
            FROM processed_stories
            ORDER BY processed_stories_id
            LIMIT 1
        """).hash()
        got_processed_stories_ids = search_solr_for_processed_stories_ids(
            db=self.DB,
            q='*:*',
            fq=None,
            last_ps_id=0,
            num_stories=1,
        )
        assert len(got_processed_stories_ids) == 1, "search_solr_for_processed_stories_ids() count"
        assert got_processed_stories_ids[0] == first_story[
            'processed_stories_id'
        ], "search_solr_for_processed_stories_ids() processed_stories_id"

    def test_search_solr_for_stories_ids(self):
        """search_solr_for_stories_ids()."""
        story = self.TEST_STORIES.pop()
        got_stories_ids = search_solr_for_stories_ids(db=self.DB, params={'q': f"stories_id:{story['stories_id']}"})
        assert [story['stories_id']] == got_stories_ids, "search_solr_for_stories_ids()"

    def test_range_queries(self):
        with pytest.raises(McQuerySolrRangeQueryException, message="Range queries should not be allowed"):
            query_solr(db=self.DB, params={'q': "publish_date:[foo TO bar]"})
