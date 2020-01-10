import abc
from typing import List

from mediawords.db import DatabaseHandler
from mediawords.dbi.downloads.store import store_content
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

from crawler_fetcher.exceptions import McCrawlerFetcherSoftError
from crawler_fetcher.handler import AbstractDownloadHandler
from crawler_fetcher.handlers.default.store_mixin import DefaultStoreMixin

log = create_logger(__name__)


class AbstractDownloadFeedHandler(DefaultStoreMixin, AbstractDownloadHandler, metaclass=abc.ABCMeta):
    """
    Handler for 'feed' downloads.

    The feed handler parses the feed and looks for the URLs of any new stories. A story is considered new if the URL or
    GUID is not already in the database for the given media source and if the story title is unique for the media source
    for the calendar week. If the story is new, a story is added to the stories table and a download with a type of
    'pending' is added to the downloads table.
    """

    @abc.abstractmethod
    def add_stories_from_feed(self, db: DatabaseHandler, download: dict, content: str) -> List[int]:
        """
        Return a list of new, to-be-fetcher story IDs that were added from the feed.

        For example, if 'syndicated' feed had three new stories, implementation would add them to "stories" table and
        return a list of story IDs that are to be fetched later.

        If helper returns an empty arrayref, '(redundant feed)' will be written instead of feed contents.
        """
        raise NotImplemented("Abstract method")

    @abc.abstractmethod
    def return_stories_to_be_extracted_from_feed(self, db: DatabaseHandler, download: dict, content: str) -> List[int]:
        """
        Return a list of stories that have to be extracted from this feed.

        For example, 'web_page' feed creates a single story for itself so it has to be extracted right away.
        """
        raise NotImplemented("Abstract method")

    def store_download(self, db: DatabaseHandler, download: dict, content: str) -> List[int]:
        download = decode_object_from_bytes_if_needed(download)
        content = decode_object_from_bytes_if_needed(content)

        downloads_id = download['downloads_id']

        log.info(f"Processing feed download {downloads_id}...")

        try:
            added_story_ids = self.add_stories_from_feed(db=db, download=download, content=content)
            story_ids_to_extract = self.add_stories_from_feed(db=db, download=download, content=content)

        except Exception as ex:

            error_message = f"Error processing feed for download {downloads_id}: {ex}"
            log.error(error_message)

            db.query("""
                UPDATE downloads
                SET state = 'feed_error',
                    error_message = %(error_message)s
                WHERE downloads_id = %(downloads_id)s
            """, {
                'error_message': error_message,
                'downloads_id': downloads_id,
            })

            # On non-soft errors (explicitly hard errors or unknown errors), pass the exception up
            if not isinstance(ex, McCrawlerFetcherSoftError):
                raise ex

            story_ids_to_extract = []

        else:

            if len(added_story_ids):
                last_new_story_time_sql = 'last_new_story_time = last_attempted_download_time, '
            else:
                last_new_story_time_sql = ''

            db.query(f"""
                UPDATE feeds
                SET {last_new_story_time_sql}
                    last_successful_download_time = GREATEST(last_successful_download_time, %(download_time)s)
                WHERE feeds_id = %(feeds_id)s
            """, {
                'download_time': download['download_time'],
                'feeds_id': download['feeds_id'],
            })

            # If no new stories, just store "(redundant feed)" to save storage space
            if len(added_story_ids) == 0:
                content = '(redundant feed)'

        # Reread the possibly updated download
        download = db.find_by_id(table='downloads', object_id=downloads_id)

        # Store the feed in any case
        store_content(db=db, download=download, content=content)

        log.info(f"Done processing feed download {downloads_id}")

        return story_ids_to_extract
