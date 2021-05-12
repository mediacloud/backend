import os

# noinspection PyPackageRequirements
import requests

from mediawords.util.log import create_logger

from .exceptions import McProgrammingError, McPermanentError, McTransientError

log = create_logger(__name__)


def __cleanup_dest_file(dest_file: str) -> None:
    if os.path.isfile(dest_file):
        try:
            os.unlink(dest_file)
        except Exception as ex:
            # Don't raise no exceptions at this point
            log.error(f"Unable to clean up a failed download at {dest_file}: {ex}")


def fetch_big_file(url: str, dest_file: str, max_size: int = 0) -> None:
    """
    Fetch a huge file from an URL to a local file.

    Raises one of the _AbstractFetchBigFileException exceptions.

    :param url: URL that points to a huge file.
    :param dest_file: Destination path to write the fetched file to.
    :param max_size: If >0, limit the file size to a defined number of bytes.
    :raise: ProgrammingError on unexpected fatal conditions.
    """

    if os.path.exists(dest_file):
        # Something's wrong with the code
        raise McProgrammingError(f"Destination file '{dest_file}' already exists.")

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
                                raise McPermanentError(f"The file is bigger than the max. size of {max_size}")

                        f.write(chunk)
                        f.flush()

    except McPermanentError as ex:

        __cleanup_dest_file(dest_file=dest_file)

        raise ex

    except requests.exceptions.RequestException as ex:

        __cleanup_dest_file(dest_file=dest_file)

        raise McTransientError(f"'requests' exception while fetching {url}: {ex}")

    except Exception as ex:

        __cleanup_dest_file(dest_file=dest_file)

        raise McTransientError(f"Unable to fetch and store {url}: {ex}")

    if not os.path.isfile(dest_file):
        __cleanup_dest_file(dest_file=dest_file)

        # There should be something here so in some way it is us that have messed up
        raise McProgrammingError(f"Fetched file {dest_file} is not here after fetching it.")
