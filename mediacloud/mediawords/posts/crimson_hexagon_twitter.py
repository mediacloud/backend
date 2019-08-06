"""Fetch twitter posts from crimson hexagon."""

import datetime

from mediawords.util.twitter import add_tweets_to_meta_tweets, get_tweet_id_from_url
import mediawords.util.parse_json
from mediawords.util.web.user_agent import UserAgent

from mediawords.util.log import create_logger

log = create_logger(__name__)


class McPostsCHTwitterDataException(Exception):
    """exception indicating an error in the external data fetched by this module."""
    pass


def fetch_posts(query: str, start_date: datetime, end_date: datetime) -> list:
    """Fetch day of tweets from crimson hexagon"""
    ch_monitor_id = int(query)

    ua = UserAgent()
    ua.set_max_size(100 * 1024 * 1024)
    ua.set_timeout(90)
    ua.set_timing([1, 2, 4, 8, 16, 32, 64, 128, 256, 512])

    config = mediawords.util.config.get_config()
    if 'crimson_hexagon' not in config or 'key' not in config['crimson_hexagon']:
        raise McPostsCHTwitterDataException("no key in mediawords.yml at //crimson_hexagon/key.")

    key = config['crimson_hexagon']['key']

    end_date = end_date + datetime.timedelta(days=1)

    start_arg = start_date.strftime('%Y-%m-%d')
    end_arg = end_date.strftime('%Y-%m-%d')

    url = ("https://api.crimsonhexagon.com/api/monitor/posts?auth=%s&id=%d&start=%s&end=%s&extendLimit=true" %
           (key, ch_monitor_id, start_arg, end_arg))

    log.debug("crimson hexagon url: " + url)

    response = ua.get(url)

    if not response.is_success():
        raise McPostsCHTwitterDataException("error fetching posts: " + response.decoded_content())

    decoded_content = response.decoded_content()

    data = dict(mediawords.util.parse_json.decode_json(decoded_content))

    if 'status' not in data or not data['status'] == 'success':
        raise McPostsCHTwitterDataException("Unknown response status: " + str(data))

    meta_tweets = data['posts']

    for mt in meta_tweets:
        mt['tweet_id'] = get_tweet_id_from_url(mt['url'])

    add_tweets_to_meta_tweets(meta_tweets)

    return meta_tweets