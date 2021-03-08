import datetime
import json
import time
from unittest import TestCase

from bs4 import BeautifulSoup
import requests_mock

from mediawords.util.log import create_logger

# noinspection PyProtectedMember
from crawler_ap.ap import (
    AssociatedPressAPI,
    _fetch_nitf_rendition,
    _process_stories,
    get_new_stories,
    McAPError,
)
from crawler_ap.config import APCrawlerConfig
from requests_mock import MockerCore

log = create_logger(__name__)


def _epoch_to_publishdate(epoch: int) -> str:
    dt = datetime.datetime.utcfromtimestamp(epoch)
    isoformat = '{d}Z'.format(d=dt.isoformat())
    return isoformat


@requests_mock.Mocker()
class TestAPFetcher(TestCase):
    """Test Class for AP Story Fetcher"""

    def __mock_story_data(self, mocker: MockerCore, feed_data: str) -> None:
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
            mocker.register_uri('GET', mock_content_url, headers=self.MOCK_RESPONSE_HEADERS, text=content_mock_body)

            # Register mock nitf responses
            mocker.register_uri('GET', mock_nitf_url, headers=self.MOCK_RESPONSE_HEADERS, text=nitf_mock_body)

    def __set_up_mocked_api(self, mocker: MockerCore):

        class MockAPCrawlerConfig(APCrawlerConfig):
            @staticmethod
            def api_key():
                return 'DUMMY'

        dummy_config = MockAPCrawlerConfig()

        self.fixture_data_dir = '/opt/mediacloud/tests/data/ap_test_fixtures/'
        self.api = AssociatedPressAPI(ap_config=dummy_config)
        self.MOCK_RESPONSE_HEADERS = {
            'Content-Type': 'application/json; charset=utf-8',
            'x-mediaapi-Q-name': 'feed',
            'x-mediaapi-Q-secondsLeft': '30',
            'x-mediaapi-Q-used': '1/100',
        }

        self.MOCK_FEED_ENDPOINT_URL = 'https://api.ap.org/media/v/content/feed'

        self.fixture_feed_data = open(self.fixture_data_dir + "test_ap_fixture_feed_data", "r").read()
        fixture_test_data = open(self.fixture_data_dir + "test_ap_fixture_test_data", "r").read()
        self.fixture_test_data = json.loads(fixture_test_data)
        self.fixture_content_data = json.loads(
            open(self.fixture_data_dir + "test_ap_fixture_content_data", "r").read())
        self.required_fields = {'guid', 'url', 'publish_date', 'title', 'description', 'text', 'content'}
        self.present_guids = set()
        self.__mock_story_data(feed_data=self.fixture_feed_data, mocker=mocker)

        # Register Feed mock endpoint
        mocker.register_uri('GET',
                            self.MOCK_FEED_ENDPOINT_URL,
                            headers=self.MOCK_RESPONSE_HEADERS,
                            text=self.fixture_feed_data)

    def test_fetch_nitf_rendition(self, mocker: MockerCore) -> None:
        """Test fetching of nitf content and that it is valid XML and correct size"""

        self.__set_up_mocked_api(mocker=mocker)

        story_item = self.fixture_data_stories[0]['item']
        nitf_content = _fetch_nitf_rendition(api=self.api, story=story_item)
        actual_nitf_content_length = 2854
        soup = BeautifulSoup(nitf_content, features="html.parser")
        body_content = soup.find('body.content').text
        assert len(body_content) == actual_nitf_content_length

    def test_process_stories(self, mocker: MockerCore) -> None:
        """Test that all stories are processed and all required fields are present"""

        self.__set_up_mocked_api(mocker=mocker)

        stories = _process_stories(api=self.api, stories=self.fixture_data_stories)

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

    def test_min_max_exception(self, mocker: MockerCore) -> None:
        """Test the get_new_stories() for proper exception of max_lookup being less than min_lookup"""

        self.__set_up_mocked_api(mocker=mocker)

        min_lookback = 86400
        max_lookback = 43200
        with self.assertRaises(McAPError) as cm:
            get_new_stories(api=self.api, min_lookback=min_lookback, max_lookback=max_lookback)
        err = cm.exception
        self.assertEqual(str(err), 'max_lookback cannot be less than min_lookback')

    def test_get_new_stories(self, mocker: MockerCore) -> None:
        """Test the main public method get_new_stories() for proper max_lookback behavior"""

        self.__set_up_mocked_api(mocker=mocker)

        max_lookback = 43200
        min_lookback = 1000

        # Change Feed Fixture data and content data so that all dates are younger than max_lookback
        fixture_feed_data = json.loads(self.fixture_feed_data)

        guid = None
        for item in fixture_feed_data['data']['items']:
            guid = item['item']['altids']['itemid']
            mock_publish_date = _epoch_to_publishdate(int(time.time() - (min_lookback + 1)))
            item['item']['firstcreated'] = mock_publish_date
            self.fixture_content_data[guid]['data']['item']['firstcreated'] = mock_publish_date
            self.fixture_test_data[guid]['publish_date'] = mock_publish_date

        assert guid, 'GUID is set.'

        self.__mock_story_data(mocker=mocker, feed_data=json.dumps(fixture_feed_data))

        # Register Feed mock endpoint
        mocker.register_uri('GET',
                            self.MOCK_FEED_ENDPOINT_URL,
                            headers=self.MOCK_RESPONSE_HEADERS,
                            text=json.dumps(fixture_feed_data))

        # Set up Mock Search Feed data and two fake story contents since all feed endpoint data is younger than
        # max_lookback and search method will be invoked
        mock_search_endpoint_url = 'https://api.ap.org/media/v/content/search'

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
        mocked_time = _epoch_to_publishdate(int(time.time()))
        fixture_search_data['data']['items'][0]['firstcreated'] = mocked_time
        mocked_content_data['fake_id_1'] = mocked_data[0]
        mocked_content_data['fake_id_1']['data']['item']['firstcreated'] = mocked_time
        mocked_content_data['fake_id_1']['data']['item']['altids']['itemid'] = 'fake_id_1'
        self.fixture_test_data['fake_id_1']['publish_date'] = mocked_time
        mock_content_url = "https://api.ap.org/media/v/content/{guid}".format(guid='fake_id_1')

        mocker.register_uri(
            'GET',
            mock_content_url,
            headers=self.MOCK_RESPONSE_HEADERS,
            text=json.dumps(mocked_content_data['fake_id_1']),
        )

        nitf_mock_body = open(self.fixture_data_dir + "test_ap_fixture_{guid}.nitf".format(guid=guid), "r").read()
        nitf_mock_body = nitf_mock_body.rstrip()

        mock_nitf_url = "https://api.ap.org/media/v/content/{guid}.{version}/download".format(
            guid='fake_id_1', version=0
        )

        mocker.register_uri('GET', mock_nitf_url, headers=self.MOCK_RESPONSE_HEADERS, text=nitf_mock_body)

        original_guid = fixture_search_data['data']['items'][1]['item']['altids']['itemid']
        self.fixture_test_data['fake_id_2'] = dict.copy(self.fixture_test_data[original_guid])
        fixture_search_data['data']['items'][1]['item']['altids']['itemid'] = 'fake_id_2'
        mocked_time = _epoch_to_publishdate(int(time.time()) - (max_lookback * 2))
        fixture_search_data['data']['items'][1]['firstcreated'] = mocked_time
        mocked_content_data['fake_id_2']['data']['item']['altids']['itemid'] = 'fake_id_2'
        mocked_content_data['fake_id_2']['data']['item']['firstcreated'] = mocked_time
        self.fixture_test_data['fake_id_2']['publish_date'] = mocked_time
        mock_content_url = "https://api.ap.org/media/v/content/{guid}".format(guid='fake_id_2')

        mocker.register_uri('GET',
                            mock_content_url,
                            headers=self.MOCK_RESPONSE_HEADERS,
                            text=json.dumps(mocked_content_data['fake_id_2']))

        nitf_mock_body = open(self.fixture_data_dir + "test_ap_fixture_{guid}.nitf".format(guid=guid), "r").read()
        nitf_mock_body = nitf_mock_body.rstrip()

        mock_nitf_url = "https://api.ap.org/media/v/content/{guid}.{version}/download".format(
            guid='fake_id_2', version=0
        )

        mocker.register_uri('GET', mock_nitf_url, headers=self.MOCK_RESPONSE_HEADERS, text=nitf_mock_body)

        original_guid = fixture_search_data['data']['items'][2]['item']['altids']['itemid']
        self.fixture_test_data['fake_id_3'] = dict.copy(self.fixture_test_data[original_guid])
        fixture_search_data['data']['items'][2]['item']['altids']['itemid'] = 'fake_id_3'
        mocked_time = _epoch_to_publishdate(int(time.time()) - (max_lookback * 3))
        fixture_search_data['data']['items'][2]['firstcreated'] = mocked_time
        mocked_content_data['fake_id_3']['data']['item']['altids']['itemid'] = 'fake_id_3'
        mocked_content_data['fake_id_3']['data']['item']['firstcreated'] = mocked_time
        self.fixture_test_data['fake_id_3']['publish_date'] = mocked_time
        mock_content_url = "https://api.ap.org/media/v/content/{guid}".format(guid='fake_id_3')

        mocker.register_uri('GET',
                            mock_content_url,
                            headers=self.MOCK_RESPONSE_HEADERS,
                            text=json.dumps(mocked_content_data['fake_id_3']))

        nitf_mock_body = open(self.fixture_data_dir + "test_ap_fixture_{guid}.nitf".format(guid=guid), "r").read()
        nitf_mock_body = nitf_mock_body.rstrip()
        mock_nitf_url = "https://api.ap.org/media/v/content/{guid}.{version}/download".format(
            guid='fake_id_3', version=0
        )

        mocker.register_uri('GET', mock_nitf_url, headers=self.MOCK_RESPONSE_HEADERS, text=nitf_mock_body)

        mocker.register_uri('GET',
                            mock_search_endpoint_url,
                            headers=self.MOCK_RESPONSE_HEADERS,
                            text=json.dumps(fixture_search_data))

        # There should only be 5 stories. The get_new_stories() method will stop processing stories once it reaches one
        # beyond the max_lookback and returns up to one story passed the max_lookback parameter
        stories = get_new_stories(api=self.api, min_lookback=min_lookback, max_lookback=max_lookback)
        assert len(stories) == 4

        # Test that all required fields were returned for each story
        for story in stories:
            for key in self.required_fields:
                assert key in story
