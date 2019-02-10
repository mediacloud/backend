import dateutil
import glob
import os
import re
from typing import List

import arrow

from mediawords.util.parse_json import encode_json, decode_json
from mediawords.util.log import create_logger
from mediawords.util.paths import mc_root_path
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class McGetPathToDataFilesException(Exception):
    """get_path_to_data_files() exception."""
    pass


class McGetDataFileException(Exception):
    """_get_data_file() exception."""
    pass


class McStoreTestDataToIndividualFilesException(Exception):
    """store_test_data_to_individual_files() exception."""
    pass


class McFetchTestDataFromIndividualFilesException(Exception):
    """fetch_test_data_from_individual_files() exception."""
    pass


def get_path_to_data_files(subdirectory: str = '') -> str:
    """Get path to where data file(s) should be stored."""

    subdirectory = decode_object_from_bytes_if_needed(subdirectory)

    path = os.path.join(mc_root_path(), 't', 'data', subdirectory)

    # Try to create just the base directory
    if not os.path.isdir(path):
        log.warning("Creating test data directory '{}'...".format(path))
        os.mkdir(path)

    if not os.path.isdir(path):
        raise McGetPathToDataFilesException(
            "Test data file path '{}' is not a directory (or doesn't exist at all).".format(path)
        )

    return path


def _get_data_file_extension() -> str:
    return '.json'


def _get_data_file(basename: str, subdirectory: str = '') -> str:
    """Get the file path corresponding to the given basename."""

    basename = decode_object_from_bytes_if_needed(basename)

    if not basename:
        raise McGetDataFileException("Basename is empty.")

    if not re.match(r'^[a-z0-9_]+$', basename):
        raise McGetDataFileException("Test data basename can only include '[a-z0-9_].")

    return os.path.join(
        get_path_to_data_files(subdirectory),
        "{}{}".format(basename, _get_data_file_extension()),
    )


def store_test_data(basename: str, data: dict, subdirectory: str = '') -> None:
    """Write the given data to disk under the given basename."""

    basename = decode_object_from_bytes_if_needed(basename)
    data = decode_object_from_bytes_if_needed(data)
    subdirectory = decode_object_from_bytes_if_needed(subdirectory)

    file_path = _get_data_file(basename=basename, subdirectory=subdirectory)
    with open(file_path, mode='w', encoding='utf-8') as f:
        f.write(encode_json(json_obj=data, pretty=True))


def fetch_test_data(basename: str, subdirectory: str = '') -> dict:
    """Fetch the given data from disk."""

    basename = decode_object_from_bytes_if_needed(basename)
    subdirectory = decode_object_from_bytes_if_needed(subdirectory)

    file_path = _get_data_file(basename=basename, subdirectory=subdirectory)
    with open(file_path, mode='r', encoding='utf-8') as f:
        return decode_json(f.read())


def __test_data_files(basename: str) -> List[str]:
    """Return list of data files under a given basename (subdirectory)."""
    basename = decode_object_from_bytes_if_needed(basename)

    glob_path_to_test_data_files = '{}/*{}'.format(
        get_path_to_data_files(subdirectory=basename),
        _get_data_file_extension(),
    )
    test_data_files = glob.glob(glob_path_to_test_data_files)

    return test_data_files


def store_test_data_to_individual_files(basename: str, data: dict) -> None:
    """Write the given data to disk under the given basename; split the data (list) into individual files."""
    basename = decode_object_from_bytes_if_needed(basename)
    data = decode_object_from_bytes_if_needed(data)

    data_dict = {}
    for story in data:
        stories_id = story.get('stories_id', None)
        if not stories_id:
            raise McStoreTestDataToIndividualFilesException("Story ID is unset for story: {}".format(story))

        if stories_id in data_dict:
            raise McStoreTestDataToIndividualFilesException(
                "Story ID is not unique (such story already exists in a dict) for story: {}".format(story)
            )

        data_dict[stories_id] = story

    # Remove all files before overwriting them (in case the new unit test contains *less* stories, we don't want old
    # files lying around)
    old_data_files = __test_data_files(basename=basename)
    log.info("Will remove old data files at path '{}': {}".format(basename, old_data_files))
    for path in old_data_files:
        os.unlink(path)

    # Write dict to files
    for index in data_dict.keys():
        store_test_data(basename=str(index), data=data_dict[index], subdirectory=basename)


def fetch_test_data_from_individual_files(basename: str) -> list:
    """Fetch the given data from disk under the given basename; join the data from individual files into a list."""
    basename = decode_object_from_bytes_if_needed(basename)

    data_files = __test_data_files(basename=basename)

    data_dict = {}

    for data_file in data_files:
        index = os.path.splitext(os.path.basename(data_file))[0]
        if not index:
            raise McFetchTestDataFromIndividualFilesException("Index is null for data file {}".format(data_file))

        data_dict[index] = fetch_test_data(basename=index, subdirectory=basename)

    data_list = []
    for value in data_dict.values():
        data_list.append(value)

    return data_list


def adjust_test_timezone(test_stories: list, test_timezone: str) -> list:
    """Adjust the publish_date of each story to be in the local time zone."""
    test_stories = decode_object_from_bytes_if_needed(test_stories)
    test_timezone = decode_object_from_bytes_if_needed(test_timezone)

    for story in test_stories:

        publish_date = story.get('publish_date', None)
        if not publish_date:
            continue

        parsed_date = arrow.get(publish_date)
        parsed_date = parsed_date.replace(tzinfo=dateutil.tz.gettz(test_timezone))

        parsed_date = parsed_date.to(tz=dateutil.tz.tzlocal())
        story['publish_date'] = parsed_date.strftime('%Y-%m-%d %H:%M:%S')

    return test_stories
