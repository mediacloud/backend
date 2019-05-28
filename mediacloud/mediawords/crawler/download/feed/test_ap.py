"""Unit tests for mediawords.crawler.download.feed.ap"""

import json
from unittest import TestCase
from bs4 import BeautifulSoup
import httpretty
import mediawords.util.config
import ap
import time



def test_ap_config_section() -> None:
    """Test config section is present for AP Fetcher"""
    config = mediawords.util.config.get_config()
    assert 'associated_press' in config, "associated_press section present in mediawords.yml"
    assert 'apikey' in config['associated_press'], "apikey keyword present in associated_press section of mediawords.yml"


def test_convert_publishdate_to_epoch() -> None:
    """Test publishdate time conversion to epoch (from UTC datetime) is correct"""
    assert ap._convert_publishdate_to_epoch('2019-01-01T12:00:00Z') == 1546344000


def test_extract_url_parameters() -> None:
    """Test parameter extraction from url"""
    url = 'https://www.google.com/page?a=5&b=abc'
    assert ap._extract_url_parameters(url) == {'a': '5', 'b': 'abc'}


class TestAPFetcher(TestCase):
    """Test Class for AP Story Fetcher"""

    def setUp(self):
        """Setup Method"""
        self._api = ap.AssociatedPressAPI()
        ap._api = self._api
        MOCK_RESPONSE_HEADERS = {'Content-Type': 'application/json; charset=utf-8',
                                 'x-mediaapi-Q-name': 'feed',
                                 'x-mediaapi-Q-secondsLeft': '30',
                                 'x-mediaapi-Q-used': '1/100'}

        fixture_feed_data = open("fixture_feed_data","r").read()
        self.fixture_data_stories = json.loads(fixture_feed_data)['data']['items']
        fixture_content_data = json.loads(open("fixture_content_data","r").read())
        self.required_fields = set(['guid','url','publish_date','title','description','text','content'])
        self.present_guids = set()

        for item in self.fixture_data_stories:
            story = item['item']
            guid = story['altids']['itemid']
            self.present_guids.add(guid)
            version = story['version']
            mock_content_url = "https://api.ap.org/media/v/content/{guid}".format(guid=guid)
            mock_nitf_url = "https://api.ap.org/media/v/content/{guid}.{version}/download".format(guid=guid,version=version)
            content_mock_body = json.dumps(fixture_content_data[guid])
            nitf_mock_body = open("fixture_{guid}.nitf".format(guid=guid),"r").read().rstrip()

            # Register mock content responses
            httpretty.register_uri(httpretty.GET, mock_content_url, adding_headers=MOCK_RESPONSE_HEADERS, body = content_mock_body)

            # Register mock nitf responses
            httpretty.register_uri(httpretty.GET, mock_nitf_url, adding_headers=MOCK_RESPONSE_HEADERS, body = nitf_mock_body)

        httpretty.enable()


    def tearDown(self) -> None:
        """Teardown method"""
        httpretty.disable()
        httpretty.reset()


    def test_fetch_nitf_rendition(self) -> None:
        """Test fetching of nitf content and that it is valid XML"""
        story_item = self.fixture_data_stories[0]['item']
        nitf_content = ap._fetch_nitf_rendition(story_item)
        soup = BeautifulSoup(nitf_content,features="html.parser")
        body_content = soup.find('body.content').text
        assert body_content


    def test_process_stories(self) -> None:
        """Test that all stories are processed and all required fields are present"""
        stories = ap._process_stories(self.fixture_data_stories)

        # Test that all stories were processed successfully
        for guid in self.present_guids:
            assert guid in stories

        # Test that all required fields were returned for each story
        for story in stories.values():
            for key in self.required_fields:
                assert key in story

