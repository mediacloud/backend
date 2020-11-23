import re
from typing import List, Optional


def parse_status_id_from_url(url: str) -> Optional[str]:
    """Try to parse a twitter status id from a url.  Return the status id or None if not found."""
    m = re.search(r'https?://(?:mobile\.)?twitter.com/.*/status/(\d+)(\?.*)?$', url)
    if m:
        return m.group(1)
    else:
        return None


def parse_screen_name_from_user_url(url: str) -> Optional[str]:
    """Try to parse a screen name from a twitter user page url."""
    m = re.search(r'https?://(?:mobile\.)?twitter.com/([^/?]+)(\?.*)?$', url)

    if m is None:
        return None

    user = m.group(1)
    if user in ('search', 'login'):
        return None

    return user


def get_tweet_urls(tweet: dict) -> List[str]:
    """Parse unique tweet urls from the tweet data.

    Looks for urls and media, in the tweet proper and in the retweeted_status.
    """
    urls = []
    for tweet in (tweet, tweet.get('retweeted_status', None), tweet.get('quoted_status', None)):
        if tweet is None:
            continue

        if 'entities' in tweet and 'urls' in tweet['entities']:
            tweet_urls = [u['expanded_url'] for u in tweet['entities']['urls']]
            urls = list(set(urls) | set(tweet_urls))
        else:
            urls = []

    urls = list(filter(lambda x: not re.match(r'https?://[^/]*twitter.com', x), urls))

    return urls
