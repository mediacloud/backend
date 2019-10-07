"""Fetch twitter posts from crimson hexagon."""

import datetime

from mediawords.util.parse_json import decode_json
from mediawords.util.web.user_agent import UserAgent
from mediawords.util.log import create_logger

from topics_mine.config import TopicsMineConfig
from topics_mine.posts import AbstractPostFetcher
from topics_mine.posts.twitter.helpers import add_tweets_to_meta_tweets, get_tweet_id_from_url

log = create_logger(__name__)


class McPostsCHTwitterDataException(Exception):
    """exception indicating an error in the external data fetched by this module."""
    pass


class CrimsonHexagonTwitterPostFetcher(AbstractPostFetcher):

    # noinspection PyMethodMayBeStatic
    def fetch_posts(self, query: str, start_date: datetime, end_date: datetime) -> list:
        """Fetch day of tweets from crimson hexagon"""
        ch_monitor_id = int(query)

        log.debug("crimson_hexagon_twitter.fetch_posts")

        ua = UserAgent()
        ua.set_max_size(100 * 1024 * 1024)
        ua.set_timeout(90)
        ua.set_timing([1, 2, 4, 8, 16, 32, 64, 128, 256, 512])

        config = TopicsMineConfig()
        api_key = config.crimson_hexagon_api_key()

        end_date = end_date + datetime.timedelta(days=1)

        start_arg = start_date.strftime('%Y-%m-%d')
        end_arg = end_date.strftime('%Y-%m-%d')

        url = ("https://api.crimsonhexagon.com/api/monitor/posts?auth=%s&id=%d&start=%s&end=%s&extendLimit=true" %
               (api_key, ch_monitor_id, start_arg, end_arg))

        log.debug("crimson hexagon url: " + url)

        response = ua.get(url)

        if not response.is_success():
            raise McPostsCHTwitterDataException("error fetching posts: " + response.decoded_content())

        decoded_content = response.decoded_content()

        data = dict(decode_json(decoded_content))

        if 'status' not in data or not data['status'] == 'success':
            raise McPostsCHTwitterDataException("Unknown response status: " + str(data))

        meta_tweets = data['posts']

        for mt in meta_tweets:
            mt['tweet_id'] = get_tweet_id_from_url(mt['url'])

        add_tweets_to_meta_tweets(meta_tweets)

        posts = []
        for mt in meta_tweets:
            log.warning("mt: %d" % mt['tweet_id'])
            if 'tweet' in mt:
                post = {
                    'post_id': mt['tweet_id'],
                    'data': mt,
                    'content': mt['tweet']['text'],
                    'publish_date': mt['tweet']['created_at'],
                    'author': mt['tweet']['user']['screen_name'],
                    'channel': mt['tweet']['user']['screen_name'],
                    'url': mt['url']
                }

                posts.append(post)

        return posts
