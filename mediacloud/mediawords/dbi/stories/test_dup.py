"""Test mediawords.db.stories.dup."""

from functools import reduce
import hashlib
import regex
from typing import List

from mediawords.dbi.stories.dup import (
    _get_title_parts,
    _get_story_date_range,
    get_medium_dup_stories_by_title,
    get_medium_dup_stories_by_url,
)


def test_get_title_parts() -> None:
    """Test get_title_parts()."""
    assert (_get_title_parts("foo") == ["foo"])
    assert (_get_title_parts("foo&amp;") == ["foo&"])
    assert (_get_title_parts("FOO") == ["foo"])
    assert (_get_title_parts("foo bar bat: bar bat foo") == ["foo bar bat: bar bat foo", "foo bar bat", "bar bat foo"])
    assert (_get_title_parts("foo bar - bar foo") == ["foo bar : bar foo", "foo bar", "bar foo"])
    assert (_get_title_parts("foo bar | bar foo") == ["foo bar : bar foo", "foo bar", "bar foo"])
    assert (_get_title_parts("watch: foo") == ["foo"])


def test_get_story_date_range() -> None:
    """Test _get_story_date_range."""
    stories = [{'publish_date': d} for d in ['2018-01-01']]
    assert _get_story_date_range(stories) == 0

    stories = [{'publish_date': d} for d in ['2018-01-01', '2018-01-02', '2018-01-03', '2018-01-04']]
    assert _get_story_date_range(stories) == 3 * 86400

    stories = [{'publish_date': d} for d in ['2018-01-03', '2019-01-02', '2018-01-02', '2018-01-04']]
    assert _get_story_date_range(stories) == 365 * 86400


def _get_dup_story(stories_id: int, title: str, publish_date: str = '2018-01-01') -> dict:
    """Return a dummy story for testing story dups."""
    url = 'http://dummy.test/' + regex.sub(r'[[:punct:]]', r'/', title)
    return {
        'stories_id': stories_id,
        'title': title,
        'url': url,
        'publish_date': publish_date
    }


def _checksum_stories(dup_stories: List[List]) -> List[int]:
    """Convert list of story lists into sortedlist of stories_id checksums."""
    checksum_list = []
    for story_list in dup_stories:
        md5_list = [int(hashlib.md5(str(s['stories_id']).encode('utf-8')).hexdigest(), 16) for s in story_list]
        checksum_list.append(reduce(lambda x, y: x + y, md5_list))

    return sorted(checksum_list)


def test_get_medium_dup_stories_by_title() -> None:
    """Test get_medium_dup_stories_by_title."""
    sa = _get_dup_story(1, 'foo')
    sb = _get_dup_story(2, 'foo bar foo bar bat')
    sc = _get_dup_story(3, 'mc times: foo bar foo bar bat')
    sd = _get_dup_story(4, 'opinion - foo bar foo bar bat')

    assert _checksum_stories(get_medium_dup_stories_by_title([sa, sb, sc])) == _checksum_stories([[sb, sc]])
    assert _checksum_stories(get_medium_dup_stories_by_title([sa, sd, sc])) == _checksum_stories([[sd, sc]])


def test_get_medium_dup_stories_by_url() -> None:
    """Test get_medium_dup_stories_by_url."""
    sa = _get_dup_story(1, 'foo')
    sb = _get_dup_story(2, 'bar')
    sc = _get_dup_story(3, 'foo')
    sd = _get_dup_story(4, 'bar')
    se = _get_dup_story(5, 'foo bar')

    assert _checksum_stories(
        get_medium_dup_stories_by_url([sa, sb, sc, sd, se])
    ) == _checksum_stories([[sa, sc], [sb, sd]])
