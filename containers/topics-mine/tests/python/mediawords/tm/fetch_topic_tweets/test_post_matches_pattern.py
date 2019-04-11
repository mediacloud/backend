#!/usr/bin/env py.test

from mediawords.tm.fetch_topic_tweets import _post_matches_pattern


def test_post_matches_pattern() -> None:
    assert not _post_matches_pattern({'pattern': 'foo'}, {'tweet': {'text': 'bar'}})
    assert _post_matches_pattern({'pattern': 'foo'}, {'tweet': {'text': 'foo bar'}})
    assert _post_matches_pattern({'pattern': 'foo'}, {'tweet': {'text': 'bar foo'}})
    assert not _post_matches_pattern({'pattern': 'foo'}, {})
