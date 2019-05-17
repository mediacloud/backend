#!/usr/bin/env python3

import requests
import json
import os
import time
import logging
import urllib.parse as urlparse
from typing import Any
from bs4 import BeautifulSoup
from mediawords.util.config import get_config

logging.basicConfig()
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

class AssociatedPressAPI:
    """Object used to interface with the Associated Press API and to return data from
    various API endpoints.
    """
    def __init__(self):

        self.api_version = '1.1'
        self.retry_limit = 5
        config = get_config()

        if 'associated_press' in config:
            self.api_key = config['associated_press'].get('apikey')

        if self.api_key is None:
            logger.error("Could not load api key from configuration file.")
            raise ValueError("API key configuration data missing for associated_press.")

    def feed(self,**kwargs) -> dict:
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
        url = 'https://api.ap.org/media/v/content/feed'.format(self.api_version)
        params = {}
        params['apikey'] = self.api_key
        params.update(kwargs)
        feed_data = self._make_request(url,params)
        return json.loads(feed_data)['data']

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

        params = {}
        params['apikey'] = self.api_key
        params.update(kwargs)
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
                response = requests.get(url,params=params)
            except Exception as e:
                logger.warning("Encountered an exception while making request to {}. Exception info: {}".format(url,e))
            else:
                if response.status_code == 200:
                    logger.debug("Successfully retrieved {}".format(url))
                    return response.content
                else:
                    logger.warning("Received HTTP status code {} when fetching {}".format(response.status_code,url))

            retries -= 1

            if retries == 0:
                logger.error("Could not fetch {} after {} attempts. Giving up.".format(url,self.retry_limit))
                raise ValueError("Could not fetch {} after {} attempts. Giving up.".format(url,self.retry_limit))

            wait_time = (self.retry_limit - retries) ** 2
            logger.info("Exponentially backing off for {} seconds.".format(wait_time))
            time.sleep(wait_time)


def get_new_stories(db=None) -> list:
    """This method fetches the latest items from the AP feed and returns a list of dicts.

    Parameters:

        db: If a db handle is passed in, this method will check for existing uuids in the
        database and only fetch stories for uuids not present in the database. If no db handle
        is passed, the script will return all stories (up to the max 100 without pagination)

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

    api = AssociatedPressAPI()
    feed_data = api.feed(page_size=100)
    items = []  # list of dict items to return

    for obj in feed_data['items']:

        item = obj['item']
        guid = item['altids']['itemid']
        version = item['version']

        # If DB handle was passed, check if this story has previously been retrieved (to avoid unnecessary API calls to content endpoint)
        if db:
            guid_exists = db.query("select 1 from stories s join media m using (media_id) where m.name = 'AP' and s.guid = %(a)s", {'a': guid}).hash()
            if guid_exists:
                logger.info('Story with guid: {} is already in the database -- skipping.')
                continue

        logger.info('Found new story (guid: {}, version: {})'.format(guid,version))

        # Get item content
        content_uri = item['uri']
        parsed_content_uri = urlparse.urlparse(content_uri)
        content_path = parsed_content_uri.path.rsplit('/',1)[-1]
        content_params = {k:v[0] for k,v in urlparse.parse_qs(parsed_content_uri.query).items()}
        logger.info("Fetching content for story (guid: {})".format(guid))
        content = json.loads(api.content(content_path,**content_params))['data']['item']
        publish_date = content['firstcreated'] # There is a first created date and a version created date (last edit datetime?)

        # Get nitf rendition for story
        nitf_href = content['renditions']['nitf']['href']
        parsed_nitf_uri = urlparse.urlparse(nitf_href)
        nitf_params = {k:v[0] for k,v in urlparse.parse_qs(parsed_nitf_uri.query).items()}
        nitf_path = "{guid}.{version}/download".format(guid=guid,version=version)
        logger.info("Fetching story text using nitf rendition (guid: {})".format(guid))
        nitf_content = api.content(nitf_path,**nitf_params).decode()

        # Extract story text from nitf XML (body.content) and create story_data object
        soup = BeautifulSoup(nitf_content,features="html.parser")

        # Create item dict for inclusion in list
        story_data = {}
        story_data['guid'] = guid
        story_data['publish_date'] = publish_date
        try:
            story_data['url'] = content['links'][0]['href'] # This is held in an array which suggests more than one link for a story is possible?
        except:
            logger.warning('No URL link found for guid {}. Using the story content URL instead.'.format(guid))
            story_data['url'] = nitf_href
        publish_date = content['firstcreated'] # There is a first created date and a version created date (last edit datetime?)
        story_data['url'] = story_url
        story_data['text'] = soup.find('body.content').text
        story_data['title'] = content['headline']
        try:
            story_data['description'] = content['headline_extended']
        except:
            logger.warning("No extended headline present for guid: {}. Setting description to an empty string.".format(guid))
            story_data['description'] = ''
        story_data['content'] = nitf_content
        items.append(story_data)

    logger.info("Returning {} new stories.".format(len(items)))
    return items
