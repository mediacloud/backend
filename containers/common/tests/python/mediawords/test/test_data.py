import os

import arrow
import dateutil

from mediawords.test.data import get_path_to_data_files, adjust_test_timezone


def test_get_path_to_data_files():
    path = get_path_to_data_files()
    assert os.path.isdir(path)
    assert os.path.isdir(os.path.join(path, 'crawler'))

    path = get_path_to_data_files(subdirectory="crawler")
    assert os.path.isdir(path)
    assert os.path.isdir(os.path.join(path, 'gv'))


def test_adjust_test_timezone():
    test_timezone = 'America/New_York'
    test_datetime = arrow.get('2009-06-08 01:57:42').replace(tzinfo=dateutil.tz.gettz(test_timezone))
    test_publish_date = test_datetime.strftime('%Y-%m-%d %H:%M:%S')
    test_stories = [
        {
            'stories_id': 1,
            'publish_date': test_publish_date,
        },
        {
            'stories_id': 2,
            # No "publish_date"
        },
    ]

    expected_datetime = test_datetime.clone().to(tz=dateutil.tz.tzlocal())
    expected_publish_date = expected_datetime.strftime('%Y-%m-%d %H:%M:%S')
    expected_test_stories = [
        {
            'stories_id': 1,
            'publish_date': expected_publish_date,
        },
        {
            'stories_id': 2,
            # No "publish_date"
        },
    ]

    actual_test_stories = adjust_test_timezone(test_stories=test_stories, test_timezone=test_timezone)

    assert expected_test_stories == actual_test_stories
