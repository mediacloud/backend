"""Test fetching verified twitter posts from Pushshift."""

from datetime import datetime

import pytest

import topics_mine.posts.pushshift_twitter as pushshift_twitter

# Reduce the page size to ensure fetch
pushshift_twitter.PS_TWITTER_PAGE_SIZE = 10


@pytest.fixture
def post_fetcher():
    """Create a fixture for the Pushshift twitter post fetcher."""

    return pushshift_twitter.PushshiftTwitterPostFetcher()


def test_build_range_query(post_fetcher) -> None:
    """Test the range query builder for the Pushshift twitter archive."""
    
    query = 'covid'
    start_date = datetime(2020, 3, 1)
    end_date = datetime(2020, 3, 2)
    
    expected_query_dict = {
        'size': pushshift_twitter.PS_TWITTER_PAGE_SIZE,
        'sort': ['_doc'],
        'query': {'bool': {'must': [
            {'match': {'text': query}},
            {'range': {'created_at': {'gte': int(start_date.timestamp())}}},
            {'range': {'created_at': {'lt': int(end_date.timestamp())}}}
        ]}}
    }

    query_dict = post_fetcher._build_range_query(query, start_date, end_date)
    assert query_dict == expected_query_dict


def test_build_id_query(post_fetcher) -> None:
    """Test the ID query builder for the Pushshift twitter archive."""

    ids = [1, 2, 3, 4, 5]

    expected_query_dict = {
        'size': pushshift_twitter.PS_TWITTER_PAGE_SIZE,
        'sort': ['_doc'],
        'query': {'ids': {'values': ids}}
    }
    
    query_dict = post_fetcher._build_id_query(ids)
    assert query_dict == expected_query_dict


def test_parse_tweets(post_fetcher) -> None:
    """Test parsing tweets into the expected post format."""

    test_tweet = {
        'created_at': '2006-03-21 03:50:00',
        'id': 20,
        'id_str': '20',
        'screen_name': 'jack',
        'text': 'just setting up my twttr'
    }

    expected_post = {
        'post_id': '20',
        'data': test_tweet,
        'content': 'just setting up my twttr',
        'publish_date': '2006-03-21T03:50:00',
        'author': 'jack',
        'channel': 'jack'
    }

    post = post_fetcher._parse_tweets([test_tweet])[0]
    assert post == expected_post


def test_get_post_urls(post_fetcher) -> None:
    """Test extracting URLs from the tweet bodies."""

    expected_urls = ['https://example.com/%d' % i for i in range(100)]
    
    posts = [{'data': {'entities': {'urls': [{'expanded_url': url}]}}} for url in expected_urls]
    posts[0]['data']['entities']['urls'].append({'expanded_url': 'https://twitter.com/some_link_1'})
    posts[1]['data']['entities']['urls'].append({'expanded_url': 'https://twitter.com/some_link_2'})

    urls = [url for post in posts for url in post_fetcher.get_post_urls(post)]
    assert urls == expected_urls

def test_fetch_posts(post_fetcher) -> None:
    """Test fetching mocked posts from the Pushshift twitter archive."""

    post_fetcher.test_mock_data(query='123')
