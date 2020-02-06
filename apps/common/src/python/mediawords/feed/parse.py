"""
Parse RSS / Atom feeds.
"""

import calendar
import io
import re
import time
from typing import Optional, List, Union

import feedparser

from mediawords.util.log import create_logger
from mediawords.util.sql import get_sql_date_from_epoch
from mediawords.util.url import is_homepage_url

log = create_logger(__name__)


class SyndicatedFeedItem(object):
    """Parsed feed item (entry) object."""

    __slots__ = [
        '__parsed_feed_entry',
    ]

    MAX_LINK_LENGTH = 1024
    MAX_GUID_LENGTH = 1024

    def __init__(self, parsed_feed_entry):
        self.__parsed_feed_entry = parsed_feed_entry

    def title(self) -> Optional[str]:
        """Return item title."""
        return self.__parsed_feed_entry.get('title', None)

    def description(self) -> Optional[str]:
        """
        Return item description or content.

        Prefers Atom's <content> or RSS's <content:encoded> as those are potentially longer; falls back to
        <description>.
        """

        description = None

        # Atom's "<content>"
        content = self.__parsed_feed_entry.get('content', None)
        if content:
            if isinstance(content, list):
                content = content[0]
                content_value = content.get('value', None)
                if content_value:
                    description = content_value

        if not description:
            # RSS's "<content:encoded>"
            content_encoded = self.__parsed_feed_entry.get('content:encoded', None)
            if content_encoded:
                description = content_encoded

        if not description:
            description = self.__parsed_feed_entry.get('description', None)

        # Don't strip HTML (old Perl implementation didn't do that)

        return description

    def _parsed_publish_date(self) -> Optional[tuple]:

        published_parsed = self.__parsed_feed_entry.get('published_parsed', None)
        if published_parsed:
            return published_parsed

        updated_parsed = self.__parsed_feed_entry.get('updated_parsed', None)
        if updated_parsed:
            return updated_parsed

        return None

    def publish_date(self) -> Optional[str]:
        """
        Return item publication date as a ISO 8601 string.

        RSS uses RFC 2822 dates but just like the Perl implementation, we normalize everything to ISO 8601.
        """
        iso8601_date = None

        published_tuple = self._parsed_publish_date()
        if published_tuple:
            iso8601_date = time.strftime("%Y-%m-%dT%H:%M:%SZ", published_tuple)

        return iso8601_date

    def publish_date_sql(self) -> Optional[str]:
        """Return item publication date as a PostgreSQL-formatted string in a local timezone."""
        postgresql_date = None

        published_tuple = self._parsed_publish_date()
        if published_tuple:
            # FIXME unfortunately, Perl's implementation would make the timezone vanish, so dates & times would get
            # stored in machine's timezone in PostgreSQL (which is set to America/New_York in production). We haven't
            # added timezone to stories.publish_date column yet so we have to keep the present buggy behavior here.
            timestamp = int(calendar.timegm(published_tuple))
            postgresql_date = get_sql_date_from_epoch(timestamp)

        return postgresql_date

    def link(self) -> Optional[str]:
        """Return item link (URL)."""
        link = self.__parsed_feed_entry.get('link', None)

        if not link:
            link = self.guid_if_valid()

        # Try to look for something that resembles a canonical URL
        if not link:
            for key in list(self.__parsed_feed_entry.keys()):
                if re.search(r'canonical.?url', key, flags=re.IGNORECASE):
                    value = self.__parsed_feed_entry.get(key, None)
                    if isinstance(value, str):
                        link = value

        if link:
            link = link[:self.MAX_LINK_LENGTH]
            link = re.sub(r'[\n\r\s]', '', link)

        return link

    def guid(self) -> Optional[str]:
        """Return item GUID (unique identifier), if any."""
        item_id = self.__parsed_feed_entry.get('id', None)

        if item_id:
            item_id = item_id[:self.MAX_GUID_LENGTH]

        return item_id

    def guid_if_valid(self) -> Optional[str]:
        """
        Return item GUID (unique identifier) if it appears to actually be unique.

        Some GUIDs are not in fact unique. Return the GUID if it looks valid or None if the GUID looks like it is not
        unique.
        """

        guid = self.guid()

        if guid:
            # Ignore it if it is a homepage URL
            if is_homepage_url(guid):
                guid = None
        else:
            # Might have been an empty string
            guid = None

        return guid


class SyndicatedFeed(object):
    """Parsed feed object."""

    __slots__ = [
        '__title',
        '__items',
    ]

    def __init__(self, content_stream: io.BytesIO):
        # If we pass "feedparser" a simple string, it might interpret it as a URL and start fetching untrusted things
        assert hasattr(content_stream, 'read'), "Input must be a stream."

        parsed_feed = feedparser.parse(content_stream)

        # "feedparser" goes as far as to consider a whitespace-filled string a valid feed. Some feeds might be
        # malformed, especially big ones (for example, some misconfigured CDNs get bored of sending us back a response
        # and cut us off in the middle of XML). To get the best of both worlds (allow "feedparser" to understand
        # malformed feeds and for it to *not* consider HTML pages as valid feeds), we test for whether the module
        # managed to determine the type of the feed, i.e. whether it's RSS, Atom, or CDF (whatever that is). If not,
        # then we assume that the feed is something funky and it's not worth it to proceed with it.
        if not parsed_feed.get('version', ''):
            raise Exception("Feed type was not determined, not proceeding further.")

        self.__title = None
        feed = parsed_feed.get('feed', None)
        if feed:
            self.__title = feed.get('title', None)

        self.__items = []
        for raw_entry in parsed_feed.get('entries', []):
            item = SyndicatedFeedItem(raw_entry)
            self.__items.append(item)

    def title(self) -> Optional[str]:
        """Return feed title."""
        return self.__title

    def items(self) -> List[SyndicatedFeedItem]:
        """Return feed items."""
        return self.__items


def parse_feed(content: Union[str, bytes]) -> Optional[SyndicatedFeed]:
    """
    Parse RSS / Atom feed after some simple munging to correct feed formatting.

    Return SyndicatedFeed object or None if the parse failed.
    """

    # MC_REWRITE_TO_PYTHON: do not decode parameter to string because we actually need bytes

    # Don't mess around with trying to guess whether the input is a valid feed as we can't determine that without
    # trying to parse it first:
    #
    # * Can't check for "<html>" to spot HTML pages as HTML pages are not required to have <html>, <html> tag could be
    #   in a different XML namespace, or a single page could (probably) even be both a HTML page and a valid RSS / Atom
    #   feed through some namespace magic;
    #
    # * Same argument with testing for <rss> / <feed> / <rdf> tags;
    #
    # * No comment / "cruft" stripping hacks as we're using a different parser now;
    #
    # * No "fix Atom content element encoding" as I wasn't sure what it did, and it didn't have any tests to cover the
    #   functionality.

    if not content:
        log.warning("Feed XML is unset.")
        return None

    if not isinstance(content, bytes):
        content = content.encode('utf-8', errors='replace')

    # Wrap content in StringIO so that the class doesn't try to fetch it as a URL
    content_stream = io.BytesIO(content)

    # FIXME external XML entities (security)?

    feed = None
    try:
        feed = SyndicatedFeed(content_stream=content_stream)
    except Exception as ex:
        log.debug(f"Feed that failed to parse: {content}")
        log.error(f"Unable to parse feed: {ex}")

    return feed
