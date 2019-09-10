import datetime
import json
import math
import time
from typing import Optional, List
import urllib.parse as urlparse

from bs4 import BeautifulSoup
import pytz
import requests
import xmltodict

from mediawords.db import DatabaseHandler
from mediawords.dbi.downloads import create_download_for_new_story
from mediawords.dbi.stories.stories import add_story
from mediawords.job import JobBroker
from mediawords.util.log import create_logger
from mediawords.util.parse_html import html_strip
from mediawords.util.web.user_agent import UserAgent

from crawler_ap.config import APCrawlerConfig

log = create_logger(__name__)

# name of associated press media source
AP_MEDIUM_NAME = 'The Associated Press'

# default params for get_new_stories
DEFAULT_MIN_LOOKBACK = 43200
DEFAULT_MAX_LOOKBACK = 129600


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

    def __init__(self, ap_config: Optional[APCrawlerConfig] = None):

        self.api_key = None
        self.api_version = '1.1'
        self.retry_limit = 5
        self.ratelimit_info = dict()
        self.ua = UserAgent()
        self.ua.set_timing([1, 2, 4, 8, 16, 32, 64, 128, 256])

        if not ap_config:
            ap_config = APCrawlerConfig()

        self.api_key = ap_config.api_key()

        if not self.api_key:
            raise McAPMissingAPIKey("API key configuration data missing for associated_press.")

    def feed(self, **kwargs) -> dict:
        """Feed API endpoint (Documentation: https://api.ap.org/media/v/docs/api/Search-and-Feed/#feed)

        METHOD: GET

        ENDPOINT PARAMETERS:

        q: Query Expression

        include, exclude: Parameters used to customize the fields returned in the response.

        text_links: Specifies the format of the text renditions (stories, captions, scripts and shotlists) to return in
        the response.  For stories, the valid value is nitf (NITF) or anpa (ANPA 1312). For captions, scripts and
        shotlists, the valid value is nitf (NITF).  The value of all returns all available formats (this is the
        default).

        page_size: The maximum number of items to return per page. The default is 10 items with a maximum of 100 per
        page.

        versions: Specifies whether to return all available versions of the content item and all ANPA filings or only
        the latest (the same story in the ANPA format may be filed multiple times; for example, with a different
        category code).

        REQUEST HEADERS:

        Accept-Encoding: Compresses the response to the gzip format. The valid value is gzip.

        """
        url = 'https://api.ap.org/media/v/content/feed'
        api_method = 'feed'
        params = {'apikey': self.api_key}
        params.update(kwargs)
        self._check_ratelimit(api_method)
        feed_data = self._make_request(url, params)
        return json.loads(feed_data)['data']

    def search(self, **kwargs) -> dict:
        """Feed API endpoint (Documentation: https://api.ap.org/media/v/docs/api/Search-and-Feed/#search)

        METHOD: GET

        ENDPOINT PARAMETERS:

        q: Query Expression

        include, exclude: Parameters used to customize the fields returned in the response.

        text_links: Specifies the format of the text renditions (stories, captions, scripts and shotlists) to return in
        the response.  For stories, the valid value is nitf (NITF) or anpa (ANPA 1312). For captions, scripts and
        shotlists, the valid value is nitf (NITF).  The value of all returns all available formats (this is the
        default).

        sort: The sort order of the returned results. By default, the results are sorted by relevance (meta.score) - the
        most relevant items first, regardless of the time period. Valid options are:

            versioncreated: desc. The latest items first (reverse chronological order).  versioncreated: asc. The oldest
            items first (chronological order).

        page_size: The maximum number of items to return per page. The default is 10 items with a maximum of 100 per
        page.

        page:. The requested page number within the set of search results. Page numbers start at 1.

        REQUEST HEADERS:

        Accept-Encoding: Compresses the response to the gzip format. The valid value is gzip.

        """
        url = 'https://api.ap.org/media/v/content/search'
        api_method = 'search'
        params = {'apikey': self.api_key}
        params.update(kwargs)
        self._check_ratelimit(api_method)
        search_data = self._make_request(url, params)
        return json.loads(search_data)['data']

    def content(self, path, **kwargs) -> Optional[str]:
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
        content_data = self._make_request(url, params)
        return content_data

    def _make_request(self,
                      url: str,
                      params: dict = None) -> Optional[str]:
        """Internal method for making API requests"""

        retries = self.retry_limit

        # Begin making request and retry up to retry limit
        while retries:

            log.debug("Making request to {} with parameters {}".format(url, params))

            try:
                response = requests.get(url, params=params, timeout=30)
            except Exception as e:
                log.warning("Encountered an exception while making request to {}. Exception info: {}".format(url, e))
            else:
                if response.status_code == 200:
                    log.debug("Successfully retrieved {}".format(url))
                    self._update_ratelimit_info(response.headers)
                    return response.content
                elif response.status_code == 403:
                    log.warning("Received a 403 (forbidden) response for {} -- skipping.".format(url))
                    return None
                else:
                    print(response.content)
                    log.warning("Received HTTP status code {} when fetching {}".format(response.status_code, url))

            retries -= 1

            if retries == 0:
                raise McAPFetchError("Could not fetch {} after {} attempts. Giving up.".format(url, self.retry_limit))

            wait_time = (self.retry_limit - retries) ** 2
            log.info("Exponentially backing off for {} seconds.".format(wait_time))
            time.sleep(wait_time)

        return None

    def _check_ratelimit(self, api_method: str) -> None:
        """Check the endpoint rate limit before making an API call to that endpoint and to wait if necessary"""
        if api_method in self.ratelimit_info:
            current_window_remaining = float(self.ratelimit_info[api_method].get('current_window_remaining', None))
            next_window = float(self.ratelimit_info[api_method].get('next_window', None))
            if current_window_remaining < 1 and next_window > time.time():
                wait_time = math.ceil(next_window - time.time())
                if wait_time > 0:
                    log.info('Rate limit for {}. Sleeping {} before next API call'.format(api_method, wait_time))
                    time.sleep(wait_time)

    def _update_ratelimit_info(self, headers):
        """Internal method to update rate limit information for an API endpoint"""
        api_method = headers['x-mediaapi-Q-name']
        calls_used, window_limit = [int(x) for x in headers['x-mediaapi-Q-used'].split('/')]

        if api_method not in self.ratelimit_info:
            self.ratelimit_info[api_method] = dict()

        self.ratelimit_info[api_method]['next_window'] = math.ceil(
            int(headers['x-mediaapi-Q-secondsLeft']) + time.time()
        )
        self.ratelimit_info[api_method]['current_window_limit'] = window_limit
        self.ratelimit_info[api_method]['current_window_remaining'] = window_limit - calls_used


def _extract_url_parameters(url: str) -> dict:
    """Internal method to extract parameters from a URL"""
    parsed_content_uri = urlparse.urlparse(url)
    params = {k: v[0] for k, v in urlparse.parse_qs(parsed_content_uri.query).items()}
    return params


def _id_exists_in_db(db: DatabaseHandler,
                     guid: str) -> bool:
    """Internal method to check if item exists in the database."""
    guid_exists = db.query(
        "select 1 from stories s join media m using (media_id) where m.name = %(b)s and s.guid = %(a)s",
        {'a': guid, 'b': AP_MEDIUM_NAME}).hash()

    if guid_exists:
        log.debug('Story with guid: {} is already in the database -- skipping story.')
        return True
    return False


def _fetch_nitf_rendition(api: AssociatedPressAPI, story: dict) -> str:
    """Internal method for fetching the nitf rendition story content. Returns the content for an nitf rendition."""
    guid = story['altids']['itemid']
    version = story['version']
    nitf_uri = story['renditions']['nitf']['href']
    nitf_params = _extract_url_parameters(nitf_uri)
    nitf_path = "{guid}.{version}/download".format(guid=guid, version=version)
    log.debug("Fetching story text using nitf rendition (guid: {})".format(guid))
    nitf_content = api.content(nitf_path, **nitf_params).decode()
    return nitf_content


def _process_stories(api: AssociatedPressAPI,
                     stories: list,
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

        # If DB handle was passed, check if this story has previously been retrieved (to avoid unnecessary API calls to
        # content endpoint)
        if db and _id_exists_in_db(db, guid):
            log.info("Story id {} is in database -- skipping.".format(guid))
            continue

        if existing_guids is not None and guid in existing_guids:
            log.info("Story id {} was previously ingested -- skipping.".format(guid))
            continue

        log.info('Found new story (guid: {}, version: {})'.format(guid, version))

        # Get story content
        content_uri = story['uri']
        content_params = _extract_url_parameters(content_uri)
        log.debug("Fetching content for story (guid: {})".format(guid))
        content = api.content(guid, **content_params)
        if content is None:
            continue
        else:
            content = json.loads(content)['data']['item']

        # There is a first created date and a version created date (last edit datetime?)
        publish_date = content['firstcreated']

        # Extract story text from nitf XML (body.content) and create story_data object
        nitf_content = _fetch_nitf_rendition(api=api, story=story)
        soup = BeautifulSoup(nitf_content, features="html.parser")
        story_data['content'] = nitf_content

        # Create item dict for inclusion in list
        story_data['guid'] = guid
        story_data['publish_date'] = publish_date
        try:
            # This is held in an array which suggests more than one link for a story is possible?
            story_data['url'] = content['links'][0]['href']
        except Exception as ex:
            log.warning('No URL link found for guid {}: {}. Using the story content URL instead.'.format(guid, ex))
            story_data['url'] = content['renditions']['nitf']['href']
        publish_age = int(time.time() - _convert_publishdate_to_epoch(publish_date))
        story_data['text'] = soup.find('body.content').text
        story_data['title'] = content['headline']
        try:
            story_data['description'] = content['headline_extended']
        except Exception as ex:
            log.warning("No extended headline present for guid {}: {}. Setting description to ''.".format(guid, ex))
            story_data['description'] = ''
        items[guid] = story_data
        if max_lookback is not None and publish_age > max_lookback:
            log.debug("Reached max_lookback limit (oldest story age is {:,} seconds). Stopping.".format(publish_age))
            break

    return items


def _fetch_stories_using_search(api: AssociatedPressAPI,
                                max_lookback: Optional[int],
                                db: DatabaseHandler = None,
                                existing_guids: set = None) -> dict:
    """Internal method to fetch additional stories from the search endpoint. Normally, this endpoint is called
    after the feed endpoint to gather additional stories. If the max_stories limit is greater than the total
    number of stories that can be fetched from the search endpoint, this method will continue gathering as many
    stories as possible and then return them all. A set of guids can be passed via the existing_guids keyword
    parameter. This helps to return an accurate number of stories that are requested via the max_stories
    parameters and helps prevents duplicate story uuids within the collection."""

    items = {}
    params = {
        'sort': 'versioncreated:desc',
        'page_size': 100,
    }

    while True:

        search_data = api.search(**params)
        if len(search_data['items']) == 0:
            break
        stories = search_data['items']
        processed_stories = _process_stories(
            api=api,
            stories=stories,
            max_lookback=max_lookback,
            db=db,
            existing_guids=existing_guids,
        )
        items.update(processed_stories)

        # Seconds since oldest creation time from feed endpoint
        vals = items.values()
        oldest_story = max([int(time.time() - _convert_publishdate_to_epoch(i['publish_date'])) for i in vals])

        if max_lookback is not None and oldest_story > max_lookback:
            break

        if 'next_page' not in search_data:
            break

        next_page_params = _extract_url_parameters(search_data['next_page'])
        params.update(next_page_params)

    return items


def _fetch_stories_using_feed(api: AssociatedPressAPI, db: DatabaseHandler = None) -> dict:
    """Internal method to fetch all stories from the feed endpoint"""
    feed_data = api.feed(page_size=100)
    stories = feed_data['items']
    items = _process_stories(api=api, stories=stories, db=db)
    return items


def _convert_publishdate_to_epoch(publish_date: str) -> int:
    """Internal method to get the age of the story's creation date in seconds"""
    publishdate_epoch = pytz.utc.localize(datetime.datetime.strptime(publish_date, "%Y-%m-%dT%H:%M:%Sz")).timestamp()
    return int(publishdate_epoch)


def get_new_stories(db: DatabaseHandler = None,
                    min_lookback: int = DEFAULT_MIN_LOOKBACK,
                    max_lookback: int = DEFAULT_MAX_LOOKBACK,
                    api: Optional[AssociatedPressAPI] = None) -> list:
    """This method fetches the latest items from the AP feed and returns a list of dicts.

    Parameters:

        db: If a db handle is passed in, this method will check for existing uuids in the
        database and only fetch stories for uuids not present in the database. If no db handle
        is passed, the script will return all stories (up to the max 100 without pagination)

        min_lookback: The minimum cutoff in seconds for new stories. New stories must be older than
        this value to be included in the return. If the firstcreated date of a story is younger
        than this value, it will be removed from the returned list

        max_lookback: Maximum lookback in seconds (defaults to 12 hours). The get_new_stories()
        method will stop searching when it finds a story in a return older than this value.

        api: optional AssociatedPressAPI instance to be used for making API calls.

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

    if not api:
        api = AssociatedPressAPI()

    start_time = time.time()
    if min_lookback is not None and max_lookback is not None and max_lookback < min_lookback:
        raise McAPError("max_lookback cannot be less than min_lookback")
    items = {}  # list of dict items to return
    feed_stories = _fetch_stories_using_feed(db=db, api=api)
    items.update(feed_stories)
    # Seconds since oldest creation time from feed endpoint
    oldest_story = max([int(time.time() - _convert_publishdate_to_epoch(i['publish_date'])) for i in items.values()])

    if max_lookback is None or oldest_story < max_lookback:
        log.debug(
            "Retrieved {} stories. Oldest story {:,} secs. Fetching older stories.".format(len(items), oldest_story))
        search_items = _fetch_stories_using_search(
            api=api,
            max_lookback=max_lookback,
            db=db,
            existing_guids=set(items.keys()),
        )
        items.update(search_items)

    list_items = sorted(list(items.values()), key=lambda k: k['publish_date'], reverse=True)
    log.info("Found {} new stories before applying min_lookback.".format(len(list_items)))
    if min_lookback is not None:
        list_items[:] = [item for item in list_items
                         if _convert_publishdate_to_epoch(item['publish_date']) < (start_time - min_lookback)]
    log.info("Returning {} new stories.".format(len(list_items)))
    return list_items


def _import_ap_story(db: DatabaseHandler, ap_story: dict) -> None:
    """Given a ap story return by get_new_stories(), add it to the database."""
    ap_medium = db.query("select * from media where name = %(a)s", {'a': AP_MEDIUM_NAME}).hash()
    ap_feed = {
        'media_id': ap_medium['media_id'],
        'name': 'API Feed',
        'active': False,
        'type': 'syndicated',
        'url': 'http://ap.com'
    }
    ap_feed = db.find_or_create('feeds', ap_feed)

    story = {
        'guid': ap_story['guid'],
        'url': ap_story['url'],
        'publish_date': ap_story['publish_date'],
        'title': ap_story['title'],
        'description': ap_story['description'],
        'media_id': ap_medium['media_id']
    }
    story = add_story(db, story, ap_feed['feeds_id'])

    if not story:
        return

    story_download = create_download_for_new_story(db, story, ap_feed)

    download_text = {
        'downloads_id': story_download['downloads_id'],
        'download_text': ap_story['text'],
        'download_text_length': len(ap_story['text'])
    }

    db.query(
        """
        insert into download_texts (downloads_id, download_text, download_text_length)
            values (%(downloads_id)s, %(download_text)s, %(download_text_length)s)
        """,
        download_text)

    # Send to the extractor for it to do vectorization, language detection, etc.
    JobBroker(queue_name='MediaWords::Job::ExtractAndVector').add_to_queue(
        stories_id=story['stories_id'],
        use_existing=True,
    )


def add_new_stories(db: DatabaseHandler, new_stories: List[dict]) -> None:
    """Add stories as returned by get_new_stories() to the database."""
    [_import_ap_story(db, s) for s in new_stories]


def import_archive_file(db: DatabaseHandler, file: str) -> None:
    """Import ap story described by xml in file into database."""
    log.debug("import ap file: %s" % file)

    with open(file) as fd:
        xml = xmltodict.parse(fd.read())

    entry = xml['sATOM']['entry']
    body = entry['content']['nitf']['body']

    story = dict()
    story['title'] = body['body.head']['hedline']['hl1']['#text']
    story['publish_date'] = entry['published']
    story['description'] = body['body.head'].get('abstract', story['title'])

    story['guid'] = entry['id'].replace('urn:publicid:ap.org:', '')
    story['url'] = entry['link']['@href'] if 'link' in entry else 'http://apnews.com/invalid/%s' % story['guid']

    # make sure body.content is the only child of body; otherwise the unparse command below will fail
    body_content = body.get('body.content', {})
    content_block = body_content['block'] if body_content is not None else {}

    content = xmltodict.unparse({'html': {'content': content_block}})

    story['text'] = html_strip(content)

    _import_ap_story(db, story)
