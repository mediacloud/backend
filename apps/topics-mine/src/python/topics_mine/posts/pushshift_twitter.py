"""Fetch verified twitter posts from Pushshift."""

import functools
from datetime import datetime

import dateutil.parser
import requests_mock

from mediawords.util.parse_json import decode_json, encode_json
from mediawords.util.web.user_agent import UserAgent
from mediawords.util.web.user_agent.request.request import Request

from topics_base.posts import get_mock_data
from topics_base.twitter_url import get_tweet_urls
from topics_mine.posts import AbstractPostFetcher

from mediawords.util.log import create_logger
log = create_logger(__name__)

PS_TWITTER_PAGE_SIZE = 10000
PS_TWITTER_SCROLL_TIMEOUT = '1m'
PS_TWITTER_SCROLL_URL = 'https://twitter-es.pushshift.io/_search/scroll'
PS_TWITTER_URL = 'https://twitter-es.pushshift.io/twitter_verified/_search?scroll=%s' % PS_TWITTER_SCROLL_TIMEOUT


class McPostsPushshiftTwitterDataException(Exception):
    """Error while interrogating the response from the Pushshift API."""
    pass


def _get_user_agent() -> UserAgent:
    """Get a properly configured user agent."""

    ua = UserAgent()
    ua.set_max_size(100 * 1024 * 1024)
    ua.set_timeout(90)
    ua.set_timing([1, 2, 4, 8, 16, 32, 64, 128, 256, 512])

    return ua


def _mock_elasticsearch_hit(post: dict) -> dict:
    """Mock an ElasticSearch hit for a Pushshift tweet."""

    return {
        '_index': 'twitter_verified',
        '_type': '_doc',
        '_id': post['post_id'],
        '_routing': post['post_id'],
        '_score': 123.456,
        '_source': {
            'id': int(post['post_id']),
            'id_str': post['post_id'],
            'screen_name': post['author'],
            'text': post['content'],
            'created_at': post['publish_date']
        }
    }


def _mock_elasticsearch_response(posts: dict, scroll_id) -> dict:
    """Mock the ElasticSearch response from the Pushshift twitter archive."""
    
    return {
        '_scroll_id': scroll_id,
        '_shards': {'total': 123, 'successful': 123, 'skipped': 0, 'failed': 0},
        'timed_out': False,
        'took': 123,
        'hits': {
            'total': {'value': len(posts), 'relation': 'eq'},
            'max_score': 123.456,
            'hits': [_mock_elasticsearch_hit(post) for post in posts]
        }
    }


def _mock_pushshift_api(request, context, post_fetcher) -> str:
    """Mock paginated Pushshift verified twitter API calls."""

    request_data = decode_json(request.text)
    scroll_id = int(request_data.get('scroll_id', 0))
    page_offset = scroll_id * PS_TWITTER_PAGE_SIZE
    
    start_date = None
    end_date = None

    mock_data = getattr(post_fetcher, '_mock_data_cache', None)
    if not mock_data:
        filters = request_data['query']['bool']['must']
        for f in filters:
            if f.get('range', {}).get('created_at', {}).get('gte'):
                start_date = datetime.fromtimestamp(f['range']['created_at']['gte'])
            if f.get('range', {}).get('created_at', {}).get('lt'):
                end_date = datetime.fromtimestamp(f['range']['created_at']['lt'])
        post_fetcher._mock_data_cache = get_mock_data(start_date, end_date)
        mock_data = post_fetcher._mock_data_cache
   
    mock_data_page = mock_data[page_offset:page_offset+PS_TWITTER_PAGE_SIZE]
    mock_posts_page = _mock_elasticsearch_response(mock_data_page, str(scroll_id + 1))

    context.status_code = 200
    context.headers = {'Content-Type': 'application/json; charset=UTF-8'}
    return encode_json(mock_posts_page)


class PushshiftTwitterPostFetcher(AbstractPostFetcher):
    """A post fetcher for the Pushshift's verified twitter archive."""

    def _build_id_query(self, ids: list) -> list:
        """Build an ElasticSearch query for specific tweet IDs."""
        
        return {
            'size': PS_TWITTER_PAGE_SIZE,
            'sort': ['_doc'],
            'query': {'ids': {'values': ids}}
        }

    def _build_range_query(self, query: dict, start_date: datetime, end_date: datetime) -> dict:
        """Build an ElasticSearch query filtered by date range."""
        
        filters = [{'match': {'text': query}}]
        if start_date:
            start_date_ts = int(start_date.timestamp())
            filters.append({'range': {'created_at': {'gte': start_date_ts}}})
        if end_date:
            end_date_ts = int(end_date.timestamp())
            filters.append({'range': {'created_at': {'lt': end_date_ts}}})

        prepared_query = {
            'size': PS_TWITTER_PAGE_SIZE,
            'sort': ['_doc'],
            'query': {'bool': {'must': filters}}
        }
        
        return prepared_query

    def _extract_quote_tweets(self, tweets: list) -> dict:
        """Find quote tweets then map IDs of the original tweet to lists of their quote tweets.
        
        Returns: {original_tweet_id:[quote_tweet_dict]}
        """

        quote_tweets = {}
        for tweet in tweets:
            if tweet.get('is_quote_status'):
                quoted_status_id = tweet.get('quoted_status_id')
                if quoted_status_id:
                    quote_tweets.setdefault(quoted_status_id, []).append(tweet)
                else:
                    log.warning('quote tweet missing quoted_status_id for id %d' % tweet['id'])
        
        return quote_tweets

    def _extract_retweets(self, tweets: list) -> dict:
        """Find retweets then map IDs of the original tweet to lists of their retweets.
        
        Returns: {original_tweet_id:[retweet_dict]}
        """

        retweets = {}
        for tweet in tweets:
            if tweet.get('is_retweet_status'):
                retweeted_status_id = tweet.get('retweeted_status_id')
                if retweeted_status_id:
                    retweets.setdefault(retweeted_status_id, []).append(tweet)
                else:
                    log.warning('retweet missing retweeted_status_id for id %d' % tweet['id'])
        
        return retweets

    def _fetch_referenced_tweets(self, tweets: list) -> None:
        """Fetch quote tweets and retweets referenced by tweets in the list.

        Since Pushshift doesn't store the referenced tweet dict for quote tweets or retweets, only
        their IDs, a second roundtrip is necessary to complete records with a referenced tweet.
        
        For example, on a quote tweet the quoted_status field isn't present, only quoted_status_id.
        Similarly, on a retweet the retweeted_status field isn't present, only retweeted_status_id.

        Returns: None, referenced tweets are stored in tweet['quoted_status'] or
        tweet['retweeted_status'] as appropriate.
        """

        log.info('fetching referenced tweets from Pushshift')

        quote_tweets = self._extract_quote_tweets(tweets)
        retweets = self._extract_retweets(tweets)
        referenced_tweet_ids = list(quote_tweets) + list(retweets)

        referenced_tweets_query_dict = self._build_id_query(referenced_tweet_ids)
        referenced_tweets = self._fetch_tweets(referenced_tweets_query_dict)

        for tweet in referenced_tweets:
            if tweet['id'] in quote_tweets:
                for quote_tweet in quote_tweets[tweet['id']]:
                    quote_tweet['quoted_status'] = tweet
            elif tweet['id'] in retweets:
                for retweet in retweets[tweet['id']]:
                    retweet['retweeted_status'] = tweet

    def _fetch_tweets(self, query_dict: dict) -> dict:
        """Request paginated tweets from the Pushshift API."""

        tweets, scroll_id = self._fetch_tweets_page(query_dict)
        while scroll_id:
            scroll_dict = {'scroll': PS_TWITTER_SCROLL_TIMEOUT, 'scroll_id': scroll_id}
            page, scroll_id = self._fetch_tweets_page(scroll_dict)
            tweets += page

        return tweets

    def _fetch_tweets_page(self, query_dict: dict) -> dict:
        """Request a single page of tweets from the Pushshift API."""

        url = PS_TWITTER_URL if 'scroll_id' not in query_dict else PS_TWITTER_SCROLL_URL
        request = Request(method='GET', url=url)
        request.set_content_type('application/json; charset=UTF-8')
        request.set_content(encode_json(query_dict))

        ua = _get_user_agent()
        response = ua.request(request)
        response_str = response.decoded_content()

        if not response.is_success():
            error_msg = 'error fetching posts: %s' % response_str
            raise McPostsPushshiftTwitterDataException(error_msg)

        response_dict = dict(decode_json(response_str))
        if 'hits' not in response_dict:
            error_msg = 'error parsing response: %s' % response_str
            raise McPostsPushshiftTwitterDataException(error_msg)
        
        shards = response_dict['_shards']
        if shards['total'] != shards['successful'] or shards['failed'] > 0:
            log.warning('total shards: {}, successful shards: {}, failed shards: {}'.format(
                shards['total'], shards['successful'], shards['failed']))

        page = [hit['_source'] for hit in response_dict['hits']['hits']]
        scroll_id = None if len(page) < PS_TWITTER_PAGE_SIZE else response_dict['_scroll_id']
        return page, scroll_id

    def _parse_tweets(self, tweets: list) -> list:
        """Parse the tweets returned from the Pushshift API."""

        posts = []
        for tweet in tweets:
            log.debug('tweet: %d' % tweet['id'])
            publish_date = dateutil.parser.parse(tweet['created_at']).isoformat()
            posts.append({
                'post_id': tweet['id_str'],
                'data': tweet,
                'content': tweet['text'],
                'publish_date': publish_date,
                'author': tweet['screen_name'],
                'channel': tweet['screen_name']
            })

        return posts

    def fetch_posts_from_api(self, query: dict, start_date: datetime, end_date: datetime) -> list:
        """Fetch posts from Pushshift's verified twitter archive."""

        log.info('fetching verified tweets from Pushshift')

        query_dict = self._build_range_query(query, start_date, end_date)
        tweets = self._fetch_tweets(query_dict)
        self._fetch_referenced_tweets(tweets)
        posts = self._parse_tweets(tweets)

        log.info('fetched %d tweets' % len(tweets))
        
        return posts

    def get_post_urls(self, post: dict) -> list:
        """Extract any URLs found in the provided post."""
        
        return get_tweet_urls(post['data'])

    def setup_mock_data(self, mocker: requests_mock.Mocker) -> None:
        """Setup mock handler for pushshift requests."""
        
        mock_fn = functools.partial(_mock_pushshift_api, post_fetcher=self)
        mocker.get(PS_TWITTER_URL, text=mock_fn)
        mocker.get(PS_TWITTER_SCROLL_URL, text=mock_fn)
    
    def validate_mock_post(self, got_post: dict, expected_post: dict) -> None:
        """Validate that a mocked post contains all expected fields and values."""

        for field in ('post_id', 'author', 'content'):
            log.debug('%s: %s <-> %s' % (field, got_post[field], expected_post[field]))
            assert got_post[field] == expected_post[field], 'field %s does not match' % field
