"""Fetch twitter posts from crimson hexagon."""

import datetime
import dateutil
from urllib.parse import parse_qs, urlparse

import requests_mock

from mediawords.util.parse_json import decode_json, encode_json
from mediawords.util.web.user_agent import UserAgent
from mediawords.util.log import create_logger

from topics_base.posts import get_mock_data
import topics_base.twitter as twitter
from topics_mine.config import TopicsMineConfig
from topics_mine.posts import AbstractPostFetcher
from topics_mine.posts.twitter.helpers import add_tweets_to_meta_tweets, get_tweet_id_from_url

log = create_logger(__name__)


class McPostsCHTwitterDataException(Exception):
    """exception indicating an error in the external data fetched by this module."""
    pass

def _mock_ch_posts(request, context) -> str:
    """Mock crimson hexagon api call for requests_mock."""
    params = parse_qs(urlparse(request.url).query)

    start_date = dateutil.parser.parse(params['start'][0])
    end_date = dateutil.parser.parse(params['end'][0])

    posts = get_mock_data(start_date, end_date)

    ch_posts = []
    for post in posts:
        url = 'http://twitter.com/%s/status/%s' % (post['author'], post['post_id'])
        p = """\
{
  "url": "%s",
  "title": "",
  "type": "Twitter",
  "language": "en",
  "assignedCategoryId": 25841371963,
  "assignedEmotionId": 25841371954,
  "categoryScores": [
    {
      "categoryId": 25841371962,
      "categoryName": "Basic Neutral",
      "score": 0
    },
    {
      "categoryId": 25841371963,
      "categoryName": "Basic Negative",
      "score": 1
    },
    {
      "categoryId": 25841371960,
      "categoryName": "Basic Positive",
      "score": 0
    }
  ],
  "emotionScores": [
    {
      "emotionId": 25841371954,
      "emotionName": "Disgust",
      "score": 0.4
    },
    {
      "emotionId": 25841371955,
      "emotionName": "Joy",
      "score": 0.01
    },
    {
      "emotionId": 25841371958,
      "emotionName": "Neutral",
      "score": 0.01
    },
    {
      "emotionId": 25841371959,
      "emotionName": "Fear",
      "score": 0.09
    },
    {
      "emotionId": 25841371956,
      "emotionName": "Sadness",
      "score": 0.22
    },
    {
      "emotionId": 25841371957,
      "emotionName": "Anger",
      "score": 0.16
    },
    {
      "emotionId": 25841371961,
      "emotionName": "Surprise",
      "score": 0.12
    }
  ]
}\
        """ % url
        ch_posts.append(p)

    context.status_code = 200
    context.headers = {'Content-Type': 'application/json; charset=UTF-8'}

    json = '{"status": "success", "posts":[%s]}' % ',\n'.join(ch_posts) 

    return json


class CrimsonHexagonTwitterPostFetcher(AbstractPostFetcher):

    def _get_content_from_api(self, query: str, start_date: datetime, end_date: datetime) -> str:
        """Fetch the posts data from thw ch api and return the http response content."""
        ch_monitor_id = int(query)

        log.debug("crimson_hexagon_twitter.fetch_posts")

        ua = UserAgent()
        ua.set_max_size(100 * 1024 * 1024)
        ua.set_timeout(90)
        ua.set_timing([1, 2, 4, 8, 16, 32, 64, 128, 256, 512])

        config = TopicsMineConfig()
        api_key = config.crimson_hexagon_api_key()

        start_arg = start_date.strftime('%Y-%m-%d')
        end_arg = end_date.strftime('%Y-%m-%d')

        url = ("https://api.crimsonhexagon.com/api/monitor/posts?auth=%s&id=%d&start=%s&end=%s&extendLimit=true" %
               (api_key, ch_monitor_id, start_arg, end_arg))

        log.debug("crimson hexagon url: " + url)

        response = ua.get(url)

        if not response.is_success():
            raise McPostsCHTwitterDataException("error fetching posts: " + response.decoded_content())

        return response.decoded_content()

    # noinspection PyMethodMayBeStatic
    def fetch_posts_from_api(self, query: str, start_date: datetime, end_date: datetime) -> list:
        """Fetch day of tweets from crimson hexagon and twitter."""
        decoded_content = self._get_content_from_api(query, start_date, end_date)

        data = dict(decode_json(decoded_content))

        if 'status' not in data or not data['status'] == 'success':
            raise McPostsCHTwitterDataException("Unknown response status: " + str(data))

        meta_tweets = data['posts']

        for mt in meta_tweets:
            mt['tweet_id'] = get_tweet_id_from_url(mt['url'])

        add_tweets_to_meta_tweets(meta_tweets)

        publish_date = dateutil.parser.parse(mt['tweet']['created_at']).isoformat()

        posts = []
        for mt in meta_tweets:
            log.debug("mt: %d" % mt['tweet_id'])
            if 'tweet' in mt:
                post = {
                    'post_id': mt['tweet_id'],
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
        # add the mocker for the ch api calls
        mocker.get('https://api.crimsonhexagon.com/api/monitor/posts', text=_mock_ch_posts)
        # seaprately we need to add the mocker for the twitter api calls
        twitter.add_mockers(mocker)

    def validate_mock_post(self, got_post: dict, expected_post: dict) -> None:
        """Ignore channel when validating mock post because twitter just copies the author into the channel field."""
        for field in ('post_id', 'author', 'content'):
            log.debug("%s: %s <-> %s" % (field, got_post[field], expected_post[field]))
            assert got_post[field] == expected_post[field], "field %s does not match" % field
