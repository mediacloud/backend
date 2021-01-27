"""Fetch twitter posts from crimson hexagon."""

import datetime
import dateutil
import re
from urllib.parse import parse_qs, urlparse, quote
from typing import Optional

import requests_mock

from mediawords.util.config import env_value
from mediawords.util.parse_json import encode_json
from mediawords.util.web.user_agent import UserAgent
from mediawords.util.web.user_agent.request.request import Request
from mediawords.util.log import create_logger

from topics_base.posts import get_mock_data
import topics_base.twitter as twitter
from topics_base.twitter_url import get_tweet_urls 
from topics_mine.config import TopicsMineConfig
from topics_mine.posts import AbstractPostFetcher
from topics_mine.posts.twitter.helpers import add_tweets_to_meta_tweets, get_tweet_id_from_url, McTwitterUrlException

log = create_logger(__name__)

"""number of posts to fetch at a time from brandwatch"""
PAGE_SIZE=5000

class McPostsBWTwitterQueryException(Exception):
    """exception indicating an error in the query sent to this module."""
    pass


class McPostsBWTwitterDataException(Exception):
    """exception indicating an error in the external data fetched by this module."""
    pass

def _mock_oauth(request, context) -> str:
    """Return simple dummy oauth response for tests."""
    context.status_code = 200
    context.headers = {'Content-Type': 'application/json; charset=UTF-8'}

    return '{"access_token":"foo","token_type":"bearer","expires_in":31535999,"scope":"read write trust"}'

def _mock_posts(request, context) -> str:
    """Mock crimson hexagon api call for requests_mock."""
    params = parse_qs(urlparse(request.url).query)

    start_date = dateutil.parser.parse(params['startDate'][0])
    end_date = dateutil.parser.parse(params['endDate'][0])

    posts = get_mock_data(start_date, end_date)

    results = ','.join(['{ "url": "http://twitter.com/%s/status/%s"}' % (p['author'], p['post_id']) for p in posts])

    context.status_code = 200
    context.headers = {'Content-Type': 'application/json; charset=UTF-8'}

    json = \
        """
        {
          "results": [%s],
          "resultsPage": 0,
          "resultsPageSize": 10,
          "resultsTotal": 6563,
          "startDate": "%s",
          "endDate": "%s"
        }
        """ % (results, start_date, end_date)

    return json

def _get_user_agent() -> UserAgent:
    """Get a properly configured user agent."""
    ua = UserAgent()
    ua.set_max_size(100 * 1024 * 1024)
    ua.set_timeout(90)
    ua.set_timing([1, 2, 4, 8, 16, 32, 64, 128, 256, 512])

    return ua


def _get_api_key() -> str:
    """Fetch the bw api key or use the cached one.

    To get a bw api key, you have to make an api call with the user and password, but the api key only lasts for
    a year, so we just get it and then cache it in a static variable, assuming that each run time will restart at least
    once a year.
    """
    if hasattr(_get_api_key, "api_key"):
        return _get_api_key.api_key

    user = env_value('MC_BRANDWATCH_USER')
    password = env_value('MC_BRANDWATCH_PASSWORD')

    log.debug(f"user: {user}")
    log.debug(f"passwod: {password}")

    ua = _get_user_agent()

    url = (
        "https://api.brandwatch.com/oauth/token?username=%s&grant_type=api-password&client_id=brandwatch-api-client" %
        (quote(user)))

    request = Request(method='POST', url=url)
    request.set_content_type('application/x-www-form-urlencoded; charset=utf-8')
    request.set_content({'password': password})

    response = ua.request(request)

    if not response.is_success():
        raise McPostsBWTwitterDataException("error fetching posts: " + response.decoded_content())

    data = dict(response.decoded_json())

    try:
        _get_api_key.api_key = data['access_token']
    except Exception as ex:
        raise McPostsBWTwitterDataException("error parsing oauth response: '%s'" % data)

    return _get_api_key.api_key


class BrandwatchTwitterPostFetcher(AbstractPostFetcher):

    def _fetch_posts_from_api_single_page(self, query: str, start_date: datetime, end_date: datetime, next_cursor: str) -> dict:
        """Fetch the posts data from thw ch api and return the http response content."""
        try:
            (project_id, query_id) = query.split('-')
            project_id = int(project_id)
            query_id = int(query_id)
        except Exception:
            raise McPostsBWTwitterQueryException(
                f"Unable to parse query '{query}', should be in 123-456, where 123 is project id and 456 is query id.")

        log.info((
            f"brandwatch_twitter.fetch_posts: "
            f"query={query} "
            f"start_date={start_date} "
            f"end_date={end_date} "
            f"next_cursor={next_cursor}"
        ))

        ua = _get_user_agent()

        api_key = _get_api_key()

        start_arg = start_date.strftime('%Y-%m-%d')
        end_arg = (end_date + datetime.timedelta(days=1)).strftime('%Y-%m-%d')

        cursor = next_cursor if next_cursor is not None else ''

        url = (
            f"https://api.brandwatch.com/projects/{project_id}/data/mentions?"
            f"queryId={query_id}&startDate={start_arg}&endDate={end_arg}&"
            f"pageSize={PAGE_SIZE}&orderBy=date&orderDirection=asc&"
            f"access_token={api_key}&cursor={cursor}")

        log.debug("brandwatch url: " + url)

        response = ua.get(url)

        if not response.is_success():
            raise McPostsBWTwitterDataException(f"error fetching posts: {response.code()} {response.status_line()}")

        data = dict(response.decoded_json())

        if 'results' not in data:
            raise McPostsBWTwitterDataException(f"error parsing response: {data}")

        log.info(f"Brandwatch API returned {len(data['results'])} rows")

        return data

    # noinspection PyMethodMayBeStatic
    def fetch_posts_from_api(
        self,
        query: str,
        start_date: datetime,
        end_date: datetime,
        sample: Optional[int] = None,
    ) -> list:
        """Fetch day of tweets from crimson hexagon and twitter."""
        meta_tweets = []
        next_cursor = None
        while True:
            data = self._fetch_posts_from_api_single_page(query, start_date, end_date, next_cursor)
            meta_tweets = meta_tweets + data['results']
            log.debug(f"Sample: {sample}; meta_tweets: {len(meta_tweets)}")

            if 'nextCursor' not in data or (sample is not None and len(meta_tweets) >= sample):
                break
            else:
                next_cursor = data['nextCursor']

        if 'results' not in data:
            raise McPostsBWTwitterDataException("Unknown response status: " + str(data))

        for mt in meta_tweets:
            try:
                mt['tweet_id'] = get_tweet_id_from_url(mt['url'])
            except McTwitterUrlException:
                raise McPostsBWTwitterQueryException(
                    """
                    Unable to parse tweet url %s. Make sure brandwatch query only includes twitter as a source.
                    """ % mt['url'])


        add_tweets_to_meta_tweets(meta_tweets)

        posts = []
        for mt in meta_tweets:
            log.debug("mt: %d" % mt['tweet_id'])
            if 'tweet' in mt:
                publish_date = dateutil.parser.parse(mt['tweet']['created_at']).isoformat()

                post = {
                    'post_id': str(mt['tweet_id']),
                    'data': mt,
                    'content': mt['tweet']['text'],
                    'publish_date': publish_date,
                    'author': mt['tweet']['user']['screen_name'],
                    'channel': mt['tweet']['user']['screen_name'],
                    'url': mt['url']
                }

                posts.append(post)

        return posts

    def setup_mock_data(self, mocker: requests_mock.Mocker) -> None:
        """Fetch tweets from ch and twitter.  Setup mocking if self.mock_enabled."""
        # add the mockers for the bw api calls
        matcher = re.compile('.*api.brandwatch.com/oauth/token.*')
        mocker.post('https://api.brandwatch.com/oauth/token', text=_mock_oauth)

        matcher = re.compile('.*api.brandwatch.com/projects.*')
        mocker.get(matcher, text=_mock_posts)

        # seaprately we need to add the mocker for the twitter api calls
        twitter.add_mockers(mocker)

    def validate_mock_post(self, got_post: dict, expected_post: dict) -> None:
        """Ignore channel when validating mock post because twitter just copies the author into the channel field."""
        for field in ('post_id', 'author', 'content'):
            log.debug("%s: %s <-> %s" % (field, got_post[field], expected_post[field]))
            assert got_post[field] == expected_post[field], "field %s does not match" % field

    def get_post_urls(self, post: dict) -> list:
        """Given a post, return a list of urls included in the post."""
        if 'data' in post['data'] and 'tweet' in post['data']['data']:
            return get_tweet_urls(post['data']['data']['tweet'])
        elif 'tweet' in post['data']:
            return get_tweet_urls(post['data']['tweet'])
        else:
            return super().get_post_urls(post)
