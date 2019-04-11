# noinspection PyUnusedLocal
import json
import re
from typing import List
from urllib.parse import parse_qs, urlparse


# noinspection PyUnusedLocal
def mock_users_lookup(request, uri, response_headers) -> List:
    """Mock twitter /users/lookup response."""
    params = parse_qs(request.body.decode('utf-8'))

    screen_names = params['screen_name'][0].split(',')

    users = []
    for screen_name in screen_names:
        m = re.match(r'.*_(\d+)$', screen_name)
        if m:
            user_id = m.group(1)
        else:
            # deal with dummy users inserted by mediawords.util.twitter.fetch_100_users() (see comments there)
            user_id = 0

        user = {
            'id': user_id,
            'name': 'test user %s' % user_id,
            'screen_name': screen_name,
            'description': "test description for user %s" % user_id}
        users.append(user)

    return [200, response_headers, json.dumps(users)]


# noinspection PyUnusedLocal
def mock_statuses_lookup(request, uri, response_headers) -> List:
    """Mock twitter /statuses/lookup response."""
    params = parse_qs(urlparse(uri).query)

    ids = params['id'][0].split(',')

    tweets = []
    for tweet_id in ids:
        tweet = {
            'id': tweet_id,
            'text': 'test content for tweet %s' % tweet_id,
            'created_at': 'Mon Dec 13 23:21:48 +0000 2010',
            'user': {'screen_name': 'user %s' % tweet_id},
            'entities': {'urls': []}}
        tweets.append(tweet)

    return [200, response_headers, json.dumps(tweets)]
