"""Test csv_generic.py"""

import datetime

from mediawords.posts.csv_generic import fetch_posts
from mediawords.util.csv import get_csv_string_from_dicts


def test_fetch_posts() -> None:
    """Test fetch_posts."""

    num_posts = 100
    start_date = datetime.datetime.strptime('2018-01-01', '%Y-%m-%d')

    expected_posts = []
    for i in range(100):
        post = {
            'post_id': str(i),
            'content': 'content for post %d' % i,
            'author': 'author %d' % i,
            'channel': 'channel %d' % i,
            'publish_date': start_date + datetime.timedelta(days=i)
        }
        expected_posts.append(post)

    posts_csv = get_csv_string_from_dicts(expected_posts)
    got_posts = fetch_posts(posts_csv, start_date, start_date + datetime.timedelta(days=num_posts))

    assert len(got_posts) == num_posts
    for i, got_post in enumerate(got_posts):
        for field in ('post_id', 'author', 'channel', 'content'):
            assert got_post[field] == expected_posts[i][field]

    got_posts = fetch_posts(posts_csv, start_date, start_date)

    assert len(got_posts) == 1
    assert got_posts[0]['post_id'] == '0'
