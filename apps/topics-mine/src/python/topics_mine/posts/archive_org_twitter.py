"""Fetch twitter posts from archive.org."""

import csv
import datetime
from urllib.parse import urlencode

from mediawords.util.log import create_logger
from mediawords.util.web.user_agent import UserAgent

from topics_mine.posts import AbstractPostFetcher
from topics_mine.posts.twitter.helpers import add_tweets_to_meta_tweets, get_tweet_id_from_url

log = create_logger(__name__)


class McPostsArchiveTwitterDataException(Exception):
    """exception indicating an error in the external data fetched by this module."""
    pass


class ArchiveOrgPostFetcher(AbstractPostFetcher):

    # noinspection PyMethodMayBeStatic
    def fetch_posts(self, query: dict, start_date: datetime, end_date: datetime) -> list:
        """Fetch tweets from archive.org that match the given query for the given day."""
        ua = UserAgent()
        ua.set_max_size(100 * 1024 * 1024)
        ua.set_timeout(90)
        ua.set_timing([1, 2, 4, 8, 16, 32, 64, 128, 256, 512])

        end_date = end_date + datetime.timedelta(days=1)

        start_arg = start_date.strftime('%Y-%m-%d')
        end_arg = end_date.strftime('%Y-%m-%d')

        enc_query = urlencode({'q': query, 'date_from': start_arg, 'date_to': end_arg})

        url = "https://searchtweets.archivelab.org/export?" + enc_query

        log.debug("archive.org url: " + url)

        response = ua.get(url)

        if not response.is_success():
            raise McPostsArchiveTwitterDataException("error fetching posts: " + response.decoded_content())

        decoded_content = response.decoded_content()

        # sometimes we get null characters, which choke the csv module
        decoded_content = decoded_content.replace('\x00', '')

        meta_tweets = []
        lines = decoded_content.splitlines()[1:]
        for row in csv.reader(lines, delimiter="\t"):
            fields = 'user_name user_screen_name lang text timestamp_ms url'.split(' ')
            meta_tweet = {}
            for i, field in enumerate(fields):
                meta_tweet[field] = row[i] if i < len(row) else ''

            if 'url' not in meta_tweet or meta_tweet['url'] == '':
                log.warning("meta_tweet '%s' does not have a url" % str(row))
                continue

            meta_tweet['tweet_id'] = get_tweet_id_from_url(meta_tweet['url'])

            meta_tweets.append(meta_tweet)

        add_tweets_to_meta_tweets(meta_tweets)

        return meta_tweets
