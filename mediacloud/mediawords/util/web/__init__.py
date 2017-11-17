from furl import furl
import os
import tempfile

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.process import run_command_in_foreground, McRunCommandInForegroundException

log = create_logger(__name__)


class McDownloadFileException(Exception):
    """download_file() exception."""
    pass


class McDownloadFileToTempPathException(McDownloadFileException):
    """download_file_to_temp_path() exception."""
    pass


def download_file(source_url: str, target_path: str) -> None:
    """Download URL to path."""

    source_url = decode_object_from_bytes_if_needed(source_url)
    target_path = decode_object_from_bytes_if_needed(target_path)

    args = ["curl",
            "--silent",
            "--show-error",
            "--fail",
            "--retry", "3",
            "--retry-delay", "5",
            "--output", target_path,
            source_url]

    try:
        run_command_in_foreground(args)
    except McRunCommandInForegroundException as ex:
        raise McDownloadFileException(
            "Error while downloading file from '%(source_url)s' to '%(target_path)s': %(exception)s" % {
                'source_url': source_url,
                'target_path': target_path,
                'exception': str(ex),
            })


def download_file_to_temp_path(source_url: str) -> str:
    """Download URL to temporary path, return that path."""

    source_url = decode_object_from_bytes_if_needed(source_url)

    dest_dir = tempfile.mkdtemp()

    # Try to figure out a sensible name for the file
    # noinspection PyBroadException
    try:
        uri = furl(source_url)
        url_path = str(uri.path)
        temp_filename = os.path.basename(url_path)
    except Exception as ex:
        log.warning("Unable to come up with filename for URL %s: %s" % (source_url, str(ex),))
        temp_filename = "temp.dat"

    dest_path = os.path.join(dest_dir, temp_filename)
    try:
        download_file(source_url=source_url, target_path=dest_path)
    except McDownloadFileException as ex:
        raise McDownloadFileToTempPathException(
            "Error while downloading file from '%(source_url)s' to temp. location '%(target_path)s': %(exception)s" % {
                'source_url': source_url,
                'target_path': dest_path,
                'exception': str(ex),
            })

    return dest_path
