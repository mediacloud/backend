import os

import requests

from mediawords.util.log import create_logger

from podcast_fetch_episode.exceptions import McPodcastFileFetchFailureException, McPodcastFileStoreFailureException

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

    Raises on exceptions.

    :param url: URL that points to a huge file.
    :param dest_file: Destination path to write the fetched file to.
    :param max_size: If >0, limit the file size to a defined number of bytes.
    """

    if os.path.exists(dest_file):
        # Something's wrong with the code
        raise McPodcastFileStoreFailureException(f"Destination file '{dest_file}' already exists.")

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
                                raise McPodcastFileFetchFailureException(
                                    f"The file is bigger than the max. size of {max_size}"
                                )

                        f.write(chunk)
                        f.flush()

    except McPodcastFileFetchFailureException as ex:

        __cleanup_dest_file(dest_file=dest_file)

        # Raise fetching failures further as they're soft exceptions
        raise McPodcastFileFetchFailureException(f"Unable to fetch {url}: {ex}")

    except requests.exceptions.RequestException as ex:

        __cleanup_dest_file(dest_file=dest_file)

        # Treat any "requests" exception as a soft failure
        raise McPodcastFileFetchFailureException(f"'requests' exception while fetching {url}: {ex}")

    except Exception as ex:

        __cleanup_dest_file(dest_file=dest_file)

        # Any other exception is assumed to be a temporary file write problem
        raise McPodcastFileStoreFailureException(f"Unable to fetch and store {url}: {ex}")

    if not os.path.isfile(dest_file):
        __cleanup_dest_file(dest_file=dest_file)

        # There should be something here so in some way it is us that have messed up
        raise McPodcastFileStoreFailureException(f"Fetched file {dest_file} is not here after fetching it.")
