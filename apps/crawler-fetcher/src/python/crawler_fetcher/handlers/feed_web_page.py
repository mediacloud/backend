import time
from typing import List

from mediawords.db import DatabaseHandler
from mediawords.dbi.stories.stories import add_story
from mediawords.util.parse_html import html_title
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.sql import sql_now

from crawler_fetcher.exceptions import McCrawlerFetcherSoftError
from crawler_fetcher.handler import AbstractDownloadHandler
from crawler_fetcher.handlers.default.fetch_mixin import DefaultFetchMixin
from crawler_fetcher.handlers.feed import AbstractDownloadFeedHandler


class DownloadFeedWebPageHandler(DefaultFetchMixin, AbstractDownloadFeedHandler, AbstractDownloadHandler):
    """Handler for 'web_page' feed downloads."""

    def add_stories_from_feed(self, db: DatabaseHandler, download: dict, content: str) -> List[int]:
        """
        Handle feeds of type 'web_page' by just creating a story to associate with the content.

        Web page feeds are feeds that consist of a web page that we download once a week and add as a story.
        """
        download = decode_object_from_bytes_if_needed(download)
        content = decode_object_from_bytes_if_needed(content)

        feeds_id = download['feeds_id']

        feed = db.find_by_id(table='feeds', object_id=feeds_id)

        title = html_title(html=content, fallback='(no title)')
        title += '[' + sql_now() + ']'

        guid = f"{str(int(time.time()))}:{download['url']}"[0:1024]

        new_story = {
            'url': download['url'],
            'guid': guid,
            'media_id': feed['media_id'],
            'publish_date': sql_now(),
            'title': title,
        }

        story = add_story(db=db, story=new_story, feeds_id=feeds_id)
        if not story:
            raise McCrawlerFetcherSoftError(f"Failed to add story {new_story}")

        db.query("""
            UPDATE downloads
            SET stories_id = %(stories_id)s,
                type = 'content'
            WHERE downloads_id = %(downloads_id)s
        """, {
            'stories_id': story['stories_id'],
            'downloads_id': download['downloads_id'],
        })

        # A webpage that was just fetched is also a story
        story_ids = [
            story['stories_id'],
        ]

        return story_ids

    def return_stories_to_be_extracted_from_feed(self, db: DatabaseHandler, download: dict, content: str) -> List[int]:
        download = decode_object_from_bytes_if_needed(download)
        # content = decode_object_from_bytes_if_needed(content)

        # Download row might have been changed by add_stories_from_feed()
        download = db.find_by_id(table='downloads', object_id=download['downloads_id'])

        # Extract web page download that was just fetched
        stories_to_extract = [
            download['stories_id'],
        ]

        return stories_to_extract
