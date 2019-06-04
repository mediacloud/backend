#!/usr/bin/env python3

import requests
import json
import sys, os
import time
import logging
import math
from collections import defaultdict
import urllib.parse as urlparse
from typing import Any
from bs4 import BeautifulSoup

import datetime
import pytz

from mediawords.db import DatabaseHandler
from mediawords.util.config import get_config
import mediawords.util.web.user_agent

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

_api = None

# name of associated press media source
AP_MEDIA_NAME = 'AP'

class McAPError(Exception):
    """Base error class"""
    pass

class McAPFetchError(McAPError):
    """AP Fetch exception error."""
    pass

class McAPMissingAPIKey(McAPError):
    """Missing API Key"""
    pass

class AssociatedPressAPI:
    """Object used to interface with the Associated Press API and to return data from
    various API endpoints.
    """
    def __init__(self):

        self.api_key = None
        self.api_version = '1.1'
        self.retry_limit = 5
        self.ratelimit_info = defaultdict(dict)
        config = get_config()
        self.ua = mediawords.util.web.user_agent.UserAgent()
        self.ua.set_timing([1, 2, 4, 8, 16, 32, 64, 128, 256])

        if 'associated_press' in config:
            self.api_key = config['associated_press'].get('apikey')

        if self.api_key is None:
            raise McAPMissingAPIKey("API key configuration data missing for associated_press.")

    def feed(self, **kwargs) -> dict:
        """Feed API endpoint (Documentation: https://api.ap.org/media/v/docs/api/Search-and-Feed/#feed)

        METHOD: GET

        ENDPOINT PARAMETERS:

        q: Query Expression

        include,exclude: Parameters used to customize the fields returned in the response.

        text_links: Specifies the format of the text renditions (stories, captions, scripts and shotlists) to return in the response.
        For stories, the valid value is nitf (NITF) or anpa (ANPA 1312). For captions, scripts and shotlists, the valid value is nitf (NITF).
        The value of all returns all available formats (this is the default).

        page_size: The maximum number of items to return per page. The default is 10 items with a maximum of 100 per page.

        versions: Specifies whether to return all available versions of the content item and all ANPA filings or only the latest
        (the same story in the ANPA format may be filed multiple times; for example, with a different category code).

        REQUEST HEADERS:

        Accept-Encoding: Compresses the response to the gzip format. The valid value is gzip.

        """
        url = 'https://api.ap.org/media/v/content/feed'
        api_method = 'feed'
        params = {'apikey': self.api_key}
        params.update(kwargs)
        self._check_ratelimit(api_method)
        feed_data = self._make_request(url,params)
        return json.loads(feed_data)['data']

    def search(self, **kwargs) -> dict:
        """Feed API endpoint (Documentation: https://api.ap.org/media/v/docs/api/Search-and-Feed/#search)

        METHOD: GET

        ENDPOINT PARAMETERS:

        q: Query Expression

        include,exclude: Parameters used to customize the fields returned in the response.

        text_links: Specifies the format of the text renditions (stories, captions, scripts and shotlists) to return in the response.
        For stories, the valid value is nitf (NITF) or anpa (ANPA 1312). For captions, scripts and shotlists, the valid value is nitf (NITF).
        The value of all returns all available formats (this is the default).

        sort: The sort order of the returned results. By default, the results are sorted by relevance (meta.score) - the most relevant items first,
        regardless of the time period. Valid options are:

            versioncreated:desc. The latest items first (reverse chronological order).
            versioncreated:asc. The oldest items first (chronological order).

        page_size: The maximum number of items to return per page. The default is 10 items with a maximum of 100 per page.

        page:. The requested page number within the set of search results. Page numbers start at 1.

        REQUEST HEADERS:

        Accept-Encoding: Compresses the response to the gzip format. The valid value is gzip.

        """
        url = 'https://api.ap.org/media/v/content/search'
        api_method = 'search'
        params = {'apikey': self.api_key}
        params.update(kwargs)
        self._check_ratelimit(api_method)
        search_data = self._make_request(url,params)
        return json.loads(search_data)['data']

    def content(self,path,**kwargs) -> dict:
        """Content API endpoint (Documentation: https://api.ap.org/media/v/docs/api/Content-Item/)
        Example: https://api.ap.org/media/v[{version}]/content/{item_id}?apikey={apikey}[{optional_parameters}]

        METHOD: GET

        ENDPOINT PARAMETERS:

        qt: Unknown. They are present in the feed response but don't appear to be in the documentation

        et: Unknown. Same as above.

        REQUEST HEADERS:

        Accept-Encoding: Compresses the response to the gzip format. The valid value is gzip.
        """

        url = 'https://api.ap.org/media/v/content/{}'.format(path)
        api_method = 'item'
        params = {'apikey': self.api_key}
        params.update(kwargs)
        self._check_ratelimit(api_method)
        content_data = self._make_request(url,params)
        return content_data

    def _make_request(self,
                      url: str,
                      params: dict = None) -> str:
        """Internal method for making API requests"""

        retries = self.retry_limit

        # Begin making request and retry up to retry limit
        while retries:

            logger.debug("Making request to {} with parameters {}".format(url,params))

            try:
                response = requests.get(url,params=params,timeout=30)
                #response = self.ua.get(url,params=params)
            except Exception as e:
                logger.warning("Encountered an exception while making request to {}. Exception info: {}".format(url,e))
            else:
                if response.status_code == 200:
                    logger.debug("Successfully retrieved {}".format(url))
                    self._update_ratelimit_info(response.headers)
                    return response.content
                elif response.status_code == 403:
                    logger.warning("Received a 403 (forbidden) response for {} -- skipping.".format(url))
                    return None
                else:
                    logger.warning("Received HTTP status code {} when fetching {}".format(response.status_code,url))

            retries -= 1

            if retries == 0:
                raise McAPFetchError("Could not fetch {} after {} attempts. Giving up.".format(url,self.retry_limit))

            wait_time = (self.retry_limit - retries) ** 2
            logger.info("Exponentially backing off for {} seconds.".format(wait_time))
            time.sleep(wait_time)

    def _check_ratelimit(self,api_method:str) -> None:
        """Internal method to check the endpoint rate limit before making an API call to that endpoint and to wait if necessary"""
        if api_method in self.ratelimit_info:
            if self.ratelimit_info[api_method]['current_window_remaining'] < 1 and self.ratelimit_info[api_method]['next_window'] > time.time():
                wait_time = math.ceil(self.ratelimit_info[api_method]['next_window'] - time.time())
                if wait_time > 0:
                    logger.info('Rate limit reached for {} endpoint. Sleeping for {} before next API call is made.'.format(api_method,wait_time))
                    time.sleep(wait_time)

    def _update_ratelimit_info(self,headers):
        """Internal method to update rate limit information for an API endpoint"""
        api_method = headers['x-mediaapi-Q-name']
        calls_used, window_limit = [int(x) for x in headers['x-mediaapi-Q-used'].split('/')]
        self.ratelimit_info[api_method]['next_window'] = math.ceil(int(headers['x-mediaapi-Q-secondsLeft']) + time.time())
        self.ratelimit_info[api_method]['current_window_limit'] = window_limit
        self.ratelimit_info[api_method]['current_window_remaining'] = window_limit - calls_used

def _extract_url_parameters(url:str) -> dict:
    """Internal method to extract parameters from a URL"""
    parsed_content_uri = urlparse.urlparse(url)
    params = {k:v[0] for k,v in urlparse.parse_qs(parsed_content_uri.query).items()}
    return params

def _id_exists_in_db(db: DatabaseHandler,
                     guid:str) -> bool:
    """Internal method to check if item exists in the database."""
    guid_exists = db.query(
	"select 1 from stories s join media m using (media_id) where m.name = %(b)s and s.guid = %(a)s",
	{'a': guid, 'b': AP_MEDIA_NAME}).hash()

    if guid_exists:
        logger.debug('Story with guid: {} is already in the database -- skipping story.')
        return True
    return False

def _fetch_nitf_rendition(story: dict,
                          db: DatabaseHandler = None) -> str:
    """Internal method for fetching the nitf rendition story content. Returns the content for an nitf rendition."""
    guid = story['altids']['itemid']
    version = story['version']
    nitf_uri = story['renditions']['nitf']['href']
    nitf_params = _extract_url_parameters(nitf_uri)
    nitf_path = "{guid}.{version}/download".format(guid=guid,version=version)
    logger.debug("Fetching story text using nitf rendition (guid: {})".format(guid))
    nitf_content = _api.content(nitf_path,**nitf_params).decode()
    return nitf_content

def _process_stories(stories: list,
                     max_lookback: int = None,
                     db: DatabaseHandler = None,
                     existing_guids: set = None) -> dict:
    """Internal method to process stories passed by the feed or search endpoint. For each story, the content
    of the story is fetched using the nitf rendition format. The stories are then formatted and returned as a dict
    where the dict key is the guid of the story. The data structure for each dictionary element is as follows:

        guid: story id
        url: public url for the story if available or the AP API content link
        publish_date
        title: headline
        description: set to headline_extended if available or ''
        text: story stripped of html tags
        content: xml for item

    When a set of guids is passed via the existing_guids keyword parameter, that set is used to prevent fetching
    previously ingested stories."""

    items = {}

    for story in stories:

        story_data = {}
        story = story['item']
        guid = story['altids']['itemid']
        version = story['version']

        # If DB handle was passed, check if this story has previously been retrieved (to avoid unnecessary API calls to content endpoint)
        if db and _id_exists_in_db(db,guid):
            continue

        if existing_guids is not None and guid in existing_guids:
            logger.info("Story id {} was previously ingested -- skipping.".format(guid))
            continue

        logger.info('Found new story (guid: {}, version: {})'.format(guid,version))

        # Get story content
        content_uri = story['uri']
        content_params = _extract_url_parameters(content_uri)
        logger.debug("Fetching content for story (guid: {})".format(guid))
        content = _api.content(guid,**content_params)
        if content is None:
            continue
        else:
            content = json.loads(content)['data']['item']
        #content = json.loads(_api.content(guid,**content_params))['data']['item']
        publish_date = content['firstcreated'] # There is a first created date and a version created date (last edit datetime?)

        # Extract story text from nitf XML (body.content) and create story_data object
        nitf_content = _fetch_nitf_rendition(story,db)
        soup = BeautifulSoup(nitf_content,features="html.parser")
        story_data['content'] = nitf_content

        # Create item dict for inclusion in list
        story_data['guid'] = guid
        story_data['publish_date'] = publish_date
        try:
            story_data['url'] = content['links'][0]['href'] # This is held in an array which suggests more than one link for a story is possible?
        except:
            logger.warning('No URL link found for guid {}. Using the story content URL instead.'.format(guid))
            story_data['url'] = content['renditions']['nitf']['href']
        publish_age = int(time.time() - _convert_publishdate_to_epoch(publish_date))
        story_data['text'] = soup.find('body.content').text
        story_data['title'] = content['headline']
        try:
            story_data['description'] = content['headline_extended']
        except:
            logger.warning("No extended headline present for guid: {}. Setting description to an empty string.".format(guid))
            story_data['description'] = ''
        items[guid] = story_data
        if max_lookback is not None and publish_age >  max_lookback:
            logger.debug("Reached max_lookback limit (oldest story age is {:,} seconds old). Stopping.".format(publish_age))
            break

    return items

def _fetch_stories_using_search(max_lookback: int,
                                db: DatabaseHandler = None,
                                existing_guids: set = None) -> dict:
    """Internal method to fetch additional stories from the search endpoint. Normally, this endpoint is called
    after the feed endpoint to gather additional stories. If the max_stories limit is greater than the total
    number of stories that can be fetched from the search endpoint, this method will continue gathering as many
    stories as possible and then return them all. A set of guids can be passed via the existing_guids keyword
    parameter. This helps to return an accurate number of stories that are requested via the max_stories
    parameters and helps prevents duplicate story uuids within the collection."""

    items = {}

    params = {"sort":"versioncreated:desc","page_size":100}

    while True:

        search_data = _api.search(**params)
        if len(search_data['items']) == 0:
            break
        stories = search_data['items']
        processed_stories = _process_stories(stories,max_lookback,db=db,existing_guids=existing_guids)
        items.update(processed_stories)
        oldest_story = max([int(time.time() - _convert_publishdate_to_epoch(item['publish_date'])) for item in items.values()]) # Seconds since oldest creation time from feed endpoint
        if oldest_story > max_lookback:
            break
        next_page_params = _extract_url_parameters(search_data['next_page'])
        params.update(next_page_params)

    return items

def _fetch_stories_using_feed(db: DatabaseHandler = None) -> dict:
    """Internal method to fetch all stories from the feed endpoint"""
    feed_data = _api.feed(page_size=100)
    stories = feed_data['items']
    items = _process_stories(stories,db=db)
    return items

def _convert_publishdate_to_epoch(publish_date: int) -> int:
    """Internal method to get the age of the story's creation date in seconds"""
    current_epoch = int(time.time())
    publishdate_epoch = pytz.utc.localize(datetime.datetime.strptime(publish_date,"%Y-%m-%dT%H:%M:%Sz")).timestamp()
    return int(publishdate_epoch)

def get_new_stories(db: DatabaseHandler = None,
                    max_lookback:int = 43200) -> list:
    """This method fetches the latest items from the AP feed and returns a list of dicts.

    Parameters:

        db: If a db handle is passed in, this method will check for existing uuids in the
        database and only fetch stories for uuids not present in the database. If no db handle
        is passed, the script will return all stories (up to the max 100 without pagination)

    max_lookback: Maximum lookback in seconds (defaults to 12 hours). The get_new_stories()
        method will stop searching when it finds a story in a return older than this value.

    Return Value:
    Each returned dict includes the following keys:

        guid: story id
        url: public url to the story
        publish_date
        title: headline
        description: headline_extended
        text: story stripped of html tags
        content: xml for item
    """
    global _api
    _api = AssociatedPressAPI()
    items = {} # list of dict items to return
    feed_stories = _fetch_stories_using_feed(db=db)
    items.update(feed_stories)
    oldest_story = max([int(time.time() - _convert_publishdate_to_epoch(item['publish_date'])) for item in items.values()]) # Seconds since oldest creation time from feed endpoint

    if oldest_story < max_lookback:
        logger.debug("Retrieved {} stories from the feed endpoint. The oldest story was {:,} seconds ago. Fetching older stories from search feed.".format(len(items),oldest_story))
        search_items = _fetch_stories_using_search(max_lookback=max_lookback, db=db, existing_guids=set(items.keys()))
        items.update(search_items)

    list_items = sorted(list(items.values()), key=lambda k: k['publish_date'],reverse=True)
    logger.info("Returning {} new stories.".format(len(list_items)))
    return list_items


def get_and_add_new_stories(db: DatabaseHandler) -> None:
    """Add stories as returend by get_new_stories() to the database."""

    ap_stories = get_new_stories( db )
    
    ap_medium = db.query( "select * from media where name = %(a)s", {'a': AP_MEDIA_NAME} ).hash();
    ap_feed = db.find_or_create('feeds', {'name': 'API Feed', 'active': False, 'type': 'syndicated'})

    for ap_story in ap_stories:
        story = {
            'guid': ap_story['guid'],
            'url': ap_story['url'],
            'publish_date': ap_story['publish_date'],
            'title': ap_story['title'],
            'description': ap_story['description'],
            'media_id': ap_medium['media_id']
        }

        story = mediawords.dbi.stories.stories.add_story(db, story, ap_feed['feeds_id'])

        story_download = {
            'state': 'success',
            'url': ap_story['url'],
            'feeds_id': ap_feed['feeds_id'],
            'stories_id': story['stories_id'],
            'type': 'content',
            'priority': 0,
            'sequence': 0,
            'extracted': True
	}

        story_download = db.create('downloads', story_download)

        download_text = {
            'downloads_id': story_download['downloads_id'],
            'download_text': ap_story['text']
	}

        download_text = db.create('download_texts', download_text)

        mediawords.storyvectors.update_story_sentences_and_language(db, story)

