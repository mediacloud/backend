from typing import List, Dict, Any

from mediawords.db import DatabaseHandler
from mediawords.dbi.downloads.store import get_media_id
from mediawords.dbi.stories.stories import add_story_and_content_download
from mediawords.feed.parse import parse_feed
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

from crawler_fetcher.exceptions import McCrawlerFetcherSoftError
from crawler_fetcher.handler import AbstractDownloadHandler
from crawler_fetcher.handlers.default.fetch_mixin import DefaultFetchMixin
from crawler_fetcher.handlers.feed import AbstractDownloadFeedHandler
from crawler_fetcher.stories_checksum import stories_checksum_matches_feed

log = create_logger(__name__)


class DownloadFeedSyndicatedHandler(DefaultFetchMixin, AbstractDownloadFeedHandler, AbstractDownloadHandler):
    """Handler for 'syndicated' feed downloads."""

    @classmethod
    def _get_stories_from_syndicated_feed(cls,
                                          content: str,
                                          media_id: int,
                                          download_time: str) -> List[Dict[str, Any]]:
        """Parse the feed. Return a list of (non-database-backed) story dicts for each story found in the feed."""
        feed = parse_feed(content)
        if not feed:
            raise McCrawlerFetcherSoftError("Unable to parse feed.")

        stories = []

        for item in feed.items():

            url = item.link()
            if not url:
                log.warning(f"URL for feed item is empty, skipping")
                continue

            guid = item.guid_if_valid()
            if not guid:
                guid = url

            title = item.title()
            if not title:
                title = '(no title)'

            description = item.description()

            publish_date = item.publish_date_sql()
            if not publish_date:
                publish_date = download_time

            story = {
                'url': url,
                'guid': guid,
                'media_id': media_id,
                'publish_date': publish_date,
                'title': title,
                'description': description,
            }
            stories.append(story)

        return stories

    def add_stories_from_feed(self, db: DatabaseHandler, download: dict, content: str) -> List[int]:
        """
        Parse the feed content; create a story dict for each parsed story; check for a new URL since the last feed
        download; if there is a new URL, check whether each story is new, and if so add it to the database and add a
        pending download for it. Return new stories that were found in the feed.
        """
        download = decode_object_from_bytes_if_needed(download)
        content = decode_object_from_bytes_if_needed(content)

        media_id = get_media_id(db=db, download=download)
        download_time = download['download_time']

        try:
            stories = self._get_stories_from_syndicated_feed(
                content=content,
                media_id=media_id,
                download_time=download_time,
            )
        except Exception as ex:
            raise McCrawlerFetcherSoftError(f"Error processing feed for {download['url']}: {ex}")

        if stories_checksum_matches_feed(db=db, feeds_id=download['feeds_id'], stories=stories):
            return []

        new_story_ids = []
        for story in stories:
            story = add_story_and_content_download(db=db, story=story, parent_download=download)
            if story.get('is_new', None):
                new_story_ids.append(story['stories_id'])

        log.debug(f"add_stories_from_feed: new stories: {len(new_story_ids)} / {len(stories)}")

        return new_story_ids

    def return_stories_to_be_extracted_from_feed(self, db: DatabaseHandler, download: dict, content: str) -> List[int]:
        # Syndicated feed itself is not a story of any sort, so nothing to extract (stories from this feed will be
        # extracted as 'content' downloads)
        return []