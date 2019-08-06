#!/usr/bin/env python3

import os
import fetch_submissions
from unittest import TestCase
import httpretty

from mediawords.util.log import create_logger
log = create_logger(__name__)


def test_epoch_conversion():
    """Test epoch conversion to UTC datetime."""
    iso_8601_date = fetch_submissions._convert_epoch_to_iso8601(1540000000)
    print(iso_8601_date)
    assert iso_8601_date == "2018-10-20 01:46:40"


class TestPushshiftRedditSubmissionFetcher(TestCase):
    '''Test Class for Pushshift Reddit Submission Fetcher'''

    def setUp(self):
        """Setup Method"""
        base_dir = os.path.dirname(os.path.realpath(__file__))
        self.fixture_data_dir = '{base_dir}/test_fixtures/'.format(base_dir=base_dir)

        self.MOCK_RESPONSE_HEADERS = {'Content-Type': 'application/json; charset=utf-8'}
        self.MOCK_SUBMISSION_ENDPOINT_URL = 'https://mediacloud.pushshift.io/rs/_search'

        self.fixture_data = open(self.fixture_data_dir + "trump_search_response.json", "r").read()

        self.required_fields = set(['post_id', 'content', 'publish_date',
                                    'author', 'channel', 'data'])
        self.present_guids = set()

        # Register Feed mock endpoint
        httpretty.register_uri(httpretty.GET, self.MOCK_SUBMISSION_ENDPOINT_URL,
                               adding_headers=self.MOCK_RESPONSE_HEADERS, body=self.fixture_data)
        httpretty.enable()

    def tearDown(self) -> None:
        """Teardown method"""
        httpretty.disable()
        httpretty.reset()

    def test_query_reddit_submissions(self) -> None:
        """Test that all submissions results are processed and all required fields are present"""
        data = fetch_submissions.query_reddit_submissions(query="trump",
                                                          start_date="2019-01-01",
                                                          end_date="2019-09-01",
                                                          sample=250)

        # Check that the number of samples returned is the number requested
        assert len(data) == 250

        # Check that all necessary fields are returned with each object
        for obj in data:
            for key in self.required_fields:
                assert key in obj

        # Check that all returned fields have non-null values
        for obj in data:
            for key in self.required_fields:
                assert obj[key] is not None

    def test_pushshift_query_builder(self) -> None:
        """Test the internal Pushshift submission search query builder method"""

        QUERY = "trump"
        QUERY_SIZE = 100
        RANDOMIZE = True
        START_DATE = "2019-01-01"
        END_DATE = "2019-07-01"

        es_query = fetch_submissions._pushshift_query_builder(query=QUERY,
                                                              size=QUERY_SIZE,
                                                              randomize=RANDOMIZE,
                                                              start_date=START_DATE,
                                                              end_date=END_DATE)

        # Check that size parameter is present and matches requested size
        assert 'size' in es_query
        assert es_query['size'] == 100

        # Check that query object has an integer random seed
        assert isinstance(es_query['query']['function_score']['random_score']['seed'], int)

        # Check that date ranges are correct
        for obj in es_query['query']['function_score']['query']['bool']['must']:
            if 'range' in obj and 'gte' in obj['range']['created_utc']:
                assert obj['range']['created_utc']['gte'] == '1546300800'
            elif 'range' in obj and 'lt' in obj['range']['created_utc']:
                assert obj['range']['created_utc']['lt'] == '1561939200'

        # Check that both title and selftext fields are included in the search
        for obj in es_query['query']['function_score']['query']['bool']['must']:
            if 'simple_query_string' in obj:
                for key in ['selftext', 'title']:
                    assert key in obj['simple_query_string']['fields']

                # Check that the default boolean operator is AND
                assert obj['simple_query_string']['default_operator'] == 'and'

                # Assert query is correct for requested search terms
                assert obj['simple_query_string']['query'] == QUERY
