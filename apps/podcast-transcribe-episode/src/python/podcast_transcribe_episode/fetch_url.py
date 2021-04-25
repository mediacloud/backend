import os

# noinspection PyPackageRequirements
import requests

from mediawords.util.log import create_logger

from .exceptions import McProgrammingError

log = create_logger(__name__)


def __cleanup_dest_file(dest_file: str) -> None:
    if os.path.isfile(dest_file):
        try:
            os.unlink(dest_file)
        except Exception as ex:
            # Don't raise no exceptions at this point
            log.error(f"Unable to clean up a failed download at {dest_file}: {ex}")


class _AbstractFetchBigFileException(Exception):
    """Base class for exceptions thrown by fetch_big_file()."""
    pass


class FileFetchError(_AbstractFetchBigFileException):
    """
    Exception thrown when we were unable to download a file.

    Is likely to happen often (due to missing files for example).
    """
    pass


class FileTooBigError(FileFetchError):
    """
    Exception thrown when the file that's being fetched is too big.
    """
    pass


class FileStoreError(_AbstractFetchBigFileException):
    """
    Exception thrown when we were unable to store the downloaded file.

    Typically a rather big problem because it means that there's something wrong with the file storage (e.g. the disk is
    out of space), but not necessarily.
    """
    pass


def fetch_big_file(url: str, dest_file: str, max_size: int = 0) -> None:
    """
    Fetch a huge file from an URL to a local file.

    Raises one of the _AbstractFetchBigFileException exceptions.

    :param url: URL that points to a huge file.
    :param dest_file: Destination path to write the fetched file to.
    :param max_size: If >0, limit the file size to a defined number of bytes.
    :raise: FileFetchError when unable to download a file.
    :raise: FileStoreError when unable to store the downloaded file.
    :raise: ProgrammingError on unexpected fatal conditions.
    """

    if os.path.exists(dest_file):
        # Something's wrong with the code
        raise FileStoreError(f"Destination file '{dest_file}' already exists.")

    try:

        # Using "requests" as our UserAgent doesn't support writing directly to files
        with requests.get(url, stream=True) as r:
            r.raise_for_status()

            bytes_read = 0

            with open(dest_file, 'wb') as f:
                for chunk in r.iter_content(chunk_size=65536):
                    # Filter out keep-alive new chunks
                    if chunk:

                        bytes_read += len(chunk)
                        if max_size:
                            if bytes_read > max_size:
                                raise FileTooBigError(f"The file is bigger than the max. size of {max_size}")

                        f.write(chunk)
                        f.flush()

    except FileTooBigError as ex:

        __cleanup_dest_file(dest_file=dest_file)

        raise ex

    except requests.exceptions.RequestException as ex:

        __cleanup_dest_file(dest_file=dest_file)

        raise FileFetchError(f"'requests' exception while fetching {url}: {ex}")

    except Exception as ex:

        __cleanup_dest_file(dest_file=dest_file)

        raise FileStoreError(f"Unable to fetch and store {url}: {ex}")

    if not os.path.isfile(dest_file):
        __cleanup_dest_file(dest_file=dest_file)

        # There should be something here so in some way it is us that have messed up
        raise McProgrammingError(f"Fetched file {dest_file} is not here after fetching it.")
