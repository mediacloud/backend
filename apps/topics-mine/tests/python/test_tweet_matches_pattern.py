# noinspection PyProtectedMember
from topics_mine.fetch_topic_tweets import _tweet_matches_pattern


def test_tweet_matches_pattern() -> None:
    assert not _tweet_matches_pattern({'topics_id': 1, 'pattern': 'foo'}, {'tweet': {'text': 'bar'}})
    assert _tweet_matches_pattern({'topics_id': 1, 'pattern': 'foo'}, {'tweet': {'text': 'foo bar'}})
    assert _tweet_matches_pattern({'topics_id': 1, 'pattern': 'foo'}, {'tweet': {'text': 'bar foo'}})
    assert not _tweet_matches_pattern({'topics_id': 1, 'pattern': 'foo'}, {})
