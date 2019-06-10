"""Unit tests for mediawords.crawler.download.feed.ap"""

import json
from unittest import TestCase
from bs4 import BeautifulSoup
import ap
import time
import datetime
import os

import httpretty

from mediawords.test.test_database import TestDatabaseWithSchemaTestCase
import mediawords.util.config

from mediawords.util.log import create_logger
log = create_logger(__name__)


def epoch_to_publishdate(epoch: int)-> str:
    dt = datetime.datetime.utcfromtimestamp(epoch)
    isoformat = '{d}Z'.format(d=dt.isoformat())
    return isoformat


def test_ap_config_section() -> None:
    """Test config section is present for AP Fetcher"""
    config = mediawords.util.config.get_config()
    assert 'associated_press' in config, "associated_press section present in mediawords.yml"
    assert 'apikey' in config['associated_press'], "apikey keyword is in associated_press section of mediawords.yml"


def test_convert_publishdate_to_epoch() -> None:
    """Test publishdate time conversion to epoch (from UTC datetime) is correct"""
    assert ap._convert_publishdate_to_epoch('2019-01-01T12:00:00Z') == 1546344000


def test_extract_url_parameters() -> None:
    """Test parameter extraction from url"""
    url = 'https://www.google.com/page?a=5&b=abc'
    assert ap._extract_url_parameters(url) == {'a': '5', 'b': 'abc'}


class TestAPFetcher(TestCase):
    """Test Class for AP Story Fetcher"""

    def mock_story_data(self, feed_data: str) -> None:
        """Mock story data from feed or search fixture data"""
        fixture_data_stories = json.loads(feed_data)['data']['items']
        self.fixture_data_stories = []

        for item in fixture_data_stories:
            self.fixture_data_stories.append(item)
            story = item['item']
            guid = story['altids']['itemid']
            self.present_guids.add(guid)
            version = story['version']
            mock_content_url = "https://api.ap.org/media/v/content/{guid}".format(guid=guid)
            mock_nitf_url = "https://api.ap.org/media/v/content/{}.{}/download".format(guid, version)
            content_mock_body = json.dumps(self.fixture_content_data[guid])
            nitf_mock_body = open(self.fixture_data_dir + "test_ap_fixture_{guid}.nitf".format(guid=guid), "r").read()
            nitf_mock_body = nitf_mock_body.rstrip()

            # Register mock content responses
            httpretty.register_uri(httpretty.GET, mock_content_url,
                                   adding_headers=self.MOCK_RESPONSE_HEADERS, body=content_mock_body)

            # Register mock nitf responses
            httpretty.register_uri(httpretty.GET, mock_nitf_url,
                                   adding_headers=self.MOCK_RESPONSE_HEADERS, body=nitf_mock_body)

    def setUp(self):
        """Setup Method"""
        config = mediawords.util.config.get_config()
        config['associated_press']['apikey'] = 'DUMMY'
        base_dir = os.path.dirname(os.path.realpath(__file__))
        self.fixture_data_dir = '{base_dir}/ap_test_fixtures/'.format(base_dir=base_dir)
        self._api = ap.AssociatedPressAPI()
        ap._api = self._api
        self.MOCK_RESPONSE_HEADERS = {'Content-Type': 'application/json; charset=utf-8',
                                      'x-mediaapi-Q-name': 'feed',
                                      'x-mediaapi-Q-secondsLeft': '30',
                                      'x-mediaapi-Q-used': '1/100'}

        self.MOCK_FEED_ENDPOINT_URL = 'https://api.ap.org/media/v/content/feed'

        self.fixture_feed_data = open(self.fixture_data_dir + "test_ap_fixture_feed_data", "r").read()
        fixture_test_data = open(self.fixture_data_dir + "test_ap_fixture_test_data", "r").read()
        self.fixture_test_data = json.loads(fixture_test_data)
        self.fixture_content_data = json.loads(
            open(self.fixture_data_dir + "test_ap_fixture_content_data", "r").read())
        self.required_fields = set(['guid', 'url', 'publish_date', 'title',
                                    'description', 'text', 'content'])
        self.present_guids = set()
        self.mock_story_data(self.fixture_feed_data)

        # Register Feed mock endpoint
        httpretty.register_uri(httpretty.GET, self.MOCK_FEED_ENDPOINT_URL,
                               adding_headers=self.MOCK_RESPONSE_HEADERS, body=self.fixture_feed_data)
        httpretty.enable()

    def tearDown(self) -> None:
        """Teardown method"""
        httpretty.disable()
        httpretty.reset()

    def test_fetch_nitf_rendition(self) -> None:
        """Test fetching of nitf content and that it is valid XML and correct size"""
        story_item = self.fixture_data_stories[0]['item']
        nitf_content = ap._fetch_nitf_rendition(story_item)
        actual_nitf_content_length = 2854
        soup = BeautifulSoup(nitf_content, features="html.parser")
        body_content = soup.find('body.content').text
        assert len(body_content) == actual_nitf_content_length

    def test_process_stories(self) -> None:
        """Test that all stories are processed and all required fields are present"""
        stories = ap._process_stories(self.fixture_data_stories)

        # Test that all stories were processed successfully
        for guid in self.present_guids:
            assert guid in stories

        # Test that all required fields were returned for each story
        for guid, story in stories.items():
            for key in self.required_fields:
                assert key in story

        # Test that each field has the correctly parsed data
        for guid, story in stories.items():
            for key in self.required_fields:
                assert self.fixture_test_data[guid][key] == story[key]

    def test_min_max_exception(self) -> None:
        """Test the get_new_stories() for proper exception of max_lookup being less than min_lookup"""
        min_lookback = 86400
        max_lookback = 43200
        with self.assertRaises(ap.McAPError) as cm:
            ap.get_new_stories(min_lookback=min_lookback, max_lookback=max_lookback)
        err = cm.exception
        self.assertEqual(str(err), 'max_lookback cannot be less than min_lookback')

    def test_get_new_stories(self) -> None:
        """Test the main public method get_new_stories() for proper max_lookback behavior"""
        MAX_LOOKBACK = 43200
        MIN_LOOKBACK = 1000
        # Change Feed Fixture data and content data so that all dates are younger than max_lookback
        fixture_feed_data = json.loads(self.fixture_feed_data)

        for item in fixture_feed_data['data']['items']:
            guid = item['item']['altids']['itemid']
            mock_publish_date = epoch_to_publishdate(int(time.time() - (MIN_LOOKBACK + 1)))
            item['item']['firstcreated'] = mock_publish_date
            self.fixture_content_data[guid]['data']['item']['firstcreated'] = mock_publish_date
            self.fixture_test_data[guid]['publish_date'] = mock_publish_date

        self.mock_story_data(json.dumps(fixture_feed_data))

        # Register Feed mock endpoint
        httpretty.register_uri(
            httpretty.GET,
            self.MOCK_FEED_ENDPOINT_URL,
            adding_headers=self.MOCK_RESPONSE_HEADERS,
            body=json.dumps(fixture_feed_data))

        # Set up Mock Search Feed data and two fake story contents since all feed endpoint data is younger than
        # max_lookback and search method will be invoked
        MOCK_SEARCH_ENDPOINT_URL = 'https://api.ap.org/media/v/content/search'

        # Fake the ids and dates so that one item is within the range and two items are older than max_lookup
        fixture_search_data = {}
        mocked_content_data = {}
        mocked_data = list(self.fixture_content_data.values())[:3]
        mocked_content_data['fake_id_1'] = mocked_data[0]
        mocked_content_data['fake_id_2'] = mocked_data[1]
        mocked_content_data['fake_id_3'] = mocked_data[2]

        fixture_search_data['data'] = {}
        fixture_search_data['data']['items'] = fixture_feed_data['data']['items'][:3]

        original_guid = fixture_search_data['data']['items'][0]['item']['altids']['itemid']
        self.fixture_test_data['fake_id_1'] = dict.copy(self.fixture_test_data[original_guid])
        fixture_search_data['data']['items'][0]['item']['altids']['itemid'] = 'fake_id_1'
        mocked_time = epoch_to_publishdate(int(time.time()))
        fixture_search_data['data']['items'][0]['firstcreated'] = mocked_time
        mocked_content_data['fake_id_1'] = mocked_data[0]
        mocked_content_data['fake_id_1']['data']['item']['firstcreated'] = mocked_time
        mocked_content_data['fake_id_1']['data']['item']['altids']['itemid'] = 'fake_id_1'
        self.fixture_test_data['fake_id_1']['publish_date'] = mocked_time
        mock_content_url = "https://api.ap.org/media/v/content/{guid}".format(guid='fake_id_1')
        httpretty.register_uri(
            httpretty.GET,
            mock_content_url,
            adding_headers=self.MOCK_RESPONSE_HEADERS,
            body=json.dumps(mocked_content_data['fake_id_1']))
        nitf_mock_body = open(self.fixture_data_dir + "test_ap_fixture_{guid}.nitf".format(guid=guid), "r").read()
        nitf_mock_body = nitf_mock_body.rstrip()

        mock_nitf_url = "https://api.ap.org/media/v/content/{guid}.{version}/download".format(
            guid='fake_id_1', version=0)
        httpretty.register_uri(httpretty.GET, mock_nitf_url,
                               adding_headers=self.MOCK_RESPONSE_HEADERS, body=nitf_mock_body)

        original_guid = fixture_search_data['data']['items'][1]['item']['altids']['itemid']
        self.fixture_test_data['fake_id_2'] = dict.copy(self.fixture_test_data[original_guid])
        fixture_search_data['data']['items'][1]['item']['altids']['itemid'] = 'fake_id_2'
        mocked_time = epoch_to_publishdate(int(time.time()) - (MAX_LOOKBACK * 2))
        fixture_search_data['data']['items'][1]['firstcreated'] = mocked_time
        mocked_content_data['fake_id_2']['data']['item']['altids']['itemid'] = 'fake_id_2'
        mocked_content_data['fake_id_2']['data']['item']['firstcreated'] = mocked_time
        self.fixture_test_data['fake_id_2']['publish_date'] = mocked_time
        mock_content_url = "https://api.ap.org/media/v/content/{guid}".format(guid='fake_id_2')
        httpretty.register_uri(
            httpretty.GET,
            mock_content_url,
            adding_headers=self.MOCK_RESPONSE_HEADERS,
            body=json.dumps(mocked_content_data['fake_id_2']))
        nitf_mock_body = open(self.fixture_data_dir + "test_ap_fixture_{guid}.nitf".format(guid=guid), "r").read()
        nitf_mock_body = nitf_mock_body.rstrip()

        mock_nitf_url = "https://api.ap.org/media/v/content/{guid}.{version}/download".format(
            guid='fake_id_2', version=0)
        httpretty.register_uri(httpretty.GET, mock_nitf_url,
                               adding_headers=self.MOCK_RESPONSE_HEADERS, body=nitf_mock_body)

        original_guid = fixture_search_data['data']['items'][2]['item']['altids']['itemid']
        self.fixture_test_data['fake_id_3'] = dict.copy(self.fixture_test_data[original_guid])
        fixture_search_data['data']['items'][2]['item']['altids']['itemid'] = 'fake_id_3'
        mocked_time = epoch_to_publishdate(int(time.time()) - (MAX_LOOKBACK * 3))
        fixture_search_data['data']['items'][2]['firstcreated'] = mocked_time
        mocked_content_data['fake_id_3']['data']['item']['altids']['itemid'] = 'fake_id_3'
        mocked_content_data['fake_id_3']['data']['item']['firstcreated'] = mocked_time
        self.fixture_test_data['fake_id_3']['publish_date'] = mocked_time
        mock_content_url = "https://api.ap.org/media/v/content/{guid}".format(guid='fake_id_3')
        httpretty.register_uri(
            httpretty.GET,
            mock_content_url,
            adding_headers=self.MOCK_RESPONSE_HEADERS,
            body=json.dumps(mocked_content_data['fake_id_3']))
        nitf_mock_body = open(self.fixture_data_dir + "test_ap_fixture_{guid}.nitf".format(guid=guid), "r").read()
        nitf_mock_body = nitf_mock_body.rstrip()
        mock_nitf_url = "https://api.ap.org/media/v/content/{guid}.{version}/download".format(
            guid='fake_id_3', version=0)
        httpretty.register_uri(httpretty.GET, mock_nitf_url,
                               adding_headers=self.MOCK_RESPONSE_HEADERS, body=nitf_mock_body)

        httpretty.register_uri(httpretty.GET, MOCK_SEARCH_ENDPOINT_URL,
                               adding_headers=self.MOCK_RESPONSE_HEADERS, body=json.dumps(fixture_search_data))

        # There should only be 5 stories. The get_new_stories() method will stop processing stories once it reaches one
        # beyond the max_lookback and returns up to one story passed the max_lookback parameter
        stories = ap.get_new_stories(min_lookback=MIN_LOOKBACK, max_lookback=MAX_LOOKBACK)
        assert len(stories) == 4

        # Test that all required fields were returned for each story
        for story in stories:
            for key in self.required_fields:
                assert key in story


def mock_get_new_stories():
    """Simple mock to return stories in the form returned by ap.get_new_stories()"""
    stories = []
    for i in range(10):
        story = {
            'url': "https://hosted.ap.org/story/%d" % i,
            'guid': "https://hosted.ap.org/guid/%d" % i,
            'title': "AP Story Title %d" % i,
            'description': "AP Story Description %d" % i,
            'publish_date': '2018-01-01 00:00:00',
            'text': "here is some ap story text for story %d" % i,
            'content': "<xml><body>here is some ap story text for story %d" % i
        }
        stories.append(story)

    return stories


class TestAPFetcherDB(TestDatabaseWithSchemaTestCase):
    """Test Class with AP mock api and database."""

    def test_get_and_add_new_stories(self) -> None:
        """Test get_and_ad_new_stories()."""
        db = self.db()

        db.create('media', {'url': 'ap.com', 'name': ap.AP_MEDIUM_NAME})

        ap_stories = mock_get_new_stories()

        ap.get_new_stories = lambda x: ap_stories

        ap.get_and_add_new_stories(db)

        stories = db.query("select * from stories").hashes()
        assert len(stories) == len(ap_stories)

        story_sentences = db.query("select * from story_sentences").hashes()
        assert len(story_sentences) == len(ap_stories)

        for ap_story in ap_stories:
            got_story = db.query("select * from stories where title = %(a)s", {'a': ap_story['title']}).hash()
            assert got_story
            for field in ['url', 'guid', 'description', 'publish_date']:
                assert got_story[field] == ap_story[field]

        # try to add the same stories
        ap.get_and_add_new_stories(db)

        # should be same number of stories, since these new ones are dups
        stories = db.query("select * from stories").hashes()
        assert len(stories) == len(ap_stories)
