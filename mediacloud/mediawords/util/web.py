from mediawords.util.log import create_logger

from mediawords.util.process import run_command_in_foreground, McRunCommandInForegroundException

l = create_logger(__name__)


class McDownloadFileException(Exception):
    pass


def download_file(source_url: str, target_path: str) -> None:
    """Download URL to path."""
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
