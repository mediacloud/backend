import unittest

import pytest
import responses

from mediawords.similarweb import similarweb, tasks
from mediawords.test.test_database import TestDatabaseWithSchemaTestCase


def test_generate_date_string_range():
    expected = ['2014-10-01', '2014-11-01', '2014-12-01', '2015-01-01', '2015-02-01']
    assert similarweb.generate_date_string_range('2014-10', '2015-02') == expected


class SimilarWebTestCase(unittest.TestCase):

    def setUp(self):
        self.good_url = 'https://www.nytimes.com/'
        self.good_domain = 'nytimes.com'
        self.bad_url = 'https://not_in_similarweb.com/'
        self.bad_domain = 'not_in_similarweb.com'
        self.start_date = '2016-08'
        self.end_date = '2016-10'
        self.good_json = {
            'meta': {
                'last_updated': '2018-01-31',
                'request': {
                    'domain': 'nytimes.com',
                    'end_date': '2016-10-31',
                    'start_date': '2016-08-01'
                },
                'domain': self.good_domain,
                'status': 'Success',
            },
            'visits': [
                {'date': '2016-08-01', 'visits': 342463250.506486},
                {'date': '2016-09-01', 'visits': 314064567.4302815},
                {'date': '2016-10-01', 'visits': 386535729.77672064}
            ]
        }
        self.bad_json = {
            'meta': {
                'error_code': 401,
                'error_message': 'Data not found',
                'request': {
                    'domain': 'not_in_similarweb.com',
                    'end_date': '2016-10-31',
                    'start_date': '2016-08-01'
                },
                'status': 'Error',
                'domain': self.bad_domain,
            },
            'visits': None
        }
        self.describe_json = {
            'response': {
                'total_traffic_and_engagement': {
                    'countries': {
                        'world': {
                            'end_date': self.end_date,
                            'fresh_data': '2018-02-05',
                            'start_date': self.start_date
                        }
                    }
                }
            }
        }
        super().setUp()

    def get_test_client(self):
        client = similarweb.SimilarWebClient(api_key='')
        responses.add(responses.GET, client.describe_url, json=self.describe_json)
        responses.add(responses.GET, client.prepare_similarweb_url(self.good_url),
                      json=self.good_json)
        responses.add(responses.GET, client.prepare_similarweb_url(self.bad_url),
                      json=self.bad_json, status=404)
        return client


class TestSimilarWebClient(SimilarWebTestCase):

    @responses.activate
    def test_good_domain(self):
        client = self.get_test_client()
        response = client.get(self.good_url)

        # just making sure the dependency injection worked
        assert response == self.good_json

    @responses.activate
    def test_bad_domain(self):
        client = self.get_test_client()
        response = client.get(self.bad_url)
        visits = response['visits']
        date_span = similarweb.generate_date_string_range(self.start_date, self.end_date)
        expected = [{'date': date, 'visits': None} for date in date_span]
        assert visits == expected

    @responses.activate
    def test_caches_dates(self):
        client = self.get_test_client()

        assert client._start_date is None
        assert client._end_date is None
        assert len(responses.calls) == 0

        client.get(self.good_url)

        assert client._start_date == self.start_date
        assert client._end_date == self.end_date

        # One call for the dates, one call for the url data
        assert len(responses.calls) == 2

        client.get(self.good_url)

        # Only one call for each additional url
        assert len(responses.calls) == 3


class TestTasks(SimilarWebTestCase, TestDatabaseWithSchemaTestCase):

    @responses.activate
    def test_bad_id(self):
        # Should fail without touching the similarweb client
        with pytest.raises(ValueError):
            tasks.update(self.db(), b'-1', None)

    @responses.activate
    def test_update_good(self):
        media = self.db().create('media', {'url': self.good_url, 'name': 'a'})
        client = self.get_test_client()
        tasks.update(self.db(), media['media_id'], client)
        result = self.db().find_by_id('similarweb_media_metrics', media['media_id'])
        visits = self.good_json['visits']
        expected_visits = int(sum(j['visits'] for j in visits) / len(visits))

        assert result['monthly_audience'] == expected_visits

    @responses.activate
    def test_update_bad(self):
        media = self.db().create('media', {'url': self.bad_url, 'name': 'a'})
        client = self.get_test_client()
        tasks.update(self.db(), media['media_id'], client)

        result = self.db().find_by_id('similarweb_media_metrics', media['media_id'])
        assert result['monthly_audience'] == 0

    @responses.activate
    def test_multiple_update(self):
        media = self.db().create('media', {'url': self.bad_url, 'name': 'a'})
        client = self.get_test_client()
        tasks.update(self.db(), media['media_id'], client)

        result = self.db().find_by_id('similarweb_media_metrics', media['media_id'])
        assert result['monthly_audience'] == 0

        responses.replace(responses.GET, client.prepare_similarweb_url(self.bad_url),
                          json=self.good_json, status=200)
        tasks.update(self.db(), media['media_id'], client)
        result = self.db().find_by_id('similarweb_media_metrics', media['media_id'])
        assert result['monthly_audience'] > 0
