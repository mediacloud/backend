#!/usr/bin/env py.test

from mediawords.db import connect_to_db
from mediawords.dbi.downloads.store import get_content_for_first_download
from mediawords.test.db.create import create_test_topic, create_test_medium, create_test_feed, create_test_story
# noinspection PyProtectedMember
from mediawords.tm.fetch_twitter_urls import _add_tweet_story


def test_add_tweet_story():
    db = connect_to_db()

    topic = create_test_topic(db, 'test')
    medium = create_test_medium(db, 'test')
    feed = create_test_feed(db, 'test', medium)
    source_story = create_test_story(db, 'source', feed)

    topics_id = topic['topics_id']

    db.create('topic_stories', {'topics_id': topics_id, 'stories_id': source_story['stories_id']})

    topic_link = {'topics_id': topics_id, 'url': 'u', 'stories_id': source_story['stories_id']}
    topic_link = db.create('topic_links', topic_link)

    tfu = {'topics_id': topics_id, 'url': 'u', 'state': 'pending', 'topic_links_id': topic_link['topic_links_id']}
    tfu = db.create('topic_fetch_urls', tfu)

    tweet = {
        'id': 123,
        'text': 'add tweet story tweet text',
        'user': {'screen_name': 'tweet screen name'},
        'created_at': 'Mon Dec 13 23:21:48 +0000 2010',
        'entities': {'urls': [{'expanded_url': 'http://direct.entity'}]},
        'retweeted_status': {'entities': {'urls': [{'expanded_url': 'http://retweeted.entity'}]}},
        'quoted_status': {'entities': {'urls': [{'expanded_url': 'http://quoted.entity'}]}}
    }

    story = _add_tweet_story(db, topic, tweet, [tfu])

    got_story = db.require_by_id('stories', story['stories_id'])

    assert got_story['title'] == "%s: %s" % (tweet['user']['screen_name'], tweet['text'])
    assert got_story['publish_date'][0:10] == '2010-12-13'
    assert got_story['url'] == 'https://twitter.com/%s/status/%s' % (tweet['user']['screen_name'], tweet['id'])
    assert got_story['guid'] == story['url']

    got_topic_link = db.require_by_id('topic_links', topic_link['topic_links_id'])
    assert got_topic_link['ref_stories_id'] == story['stories_id']

    assert get_content_for_first_download(db, story) == tweet['text']

    got_topic_story = db.query(
        "select * from topic_stories where stories_id = %(a)s and topics_id = %(b)s",
        {'a': story['stories_id'], 'b': topic['topics_id']}).hash()
    assert got_topic_story is not None
    assert got_topic_story['link_mined']

    # noinspection PyTypeChecker
    for url in [tweet['entities']['urls'][0]['expanded_url'],
                tweet['retweeted_status']['entities']['urls'][0]['expanded_url'],
                tweet['quoted_status']['entities']['urls'][0]['expanded_url']]:
        got_topic_link = db.query(
            "select * from topic_links where topics_id = %(a)s and url = %(b)s",
            {'a': topic['topics_id'], 'b': url}).hash()
        assert got_topic_link is not None
