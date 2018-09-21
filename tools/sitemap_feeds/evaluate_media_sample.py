#!/usr/bin/env python3

"""Sitemap feed evaluation."""

# FIXME Gzipped sitemaps
# FIXME namespace handling
# FIXME asyncio
import abc
import datetime
import html
import re
import xml.parsers.expat
from dataclasses import dataclass, field
from typing import Set, List, Dict, Optional

import dateutil
from furl import furl
from lxml import etree

from mediawords.util.log import create_logger
from mediawords.util.url import normalize_url, is_homepage_url, fix_common_url_mistakes, is_http_url
from mediawords.util.web.user_agent import UserAgent

log = create_logger(__name__)


class McSitemapURLsFromRobotsTxtException(Exception):
    pass


class McStoriesFromStoriesSitemapException(Exception):
    pass


@dataclass(frozen=True)
class SitemapStory(object):
    """Single sitemap-derived story."""

    url: str
    """Story URL."""

    title: str
    """Story title."""

    publish_date: datetime.datetime
    """Story publication date."""

    publication_name: str
    """Name of the news publication in which the article appears in."""

    publication_language: str
    """Primary language of the news publication in which the article appears in.

    It should be an ISO 639 Language Code (either 2 or 3 letters)."""

    access: str
    """Accessibility of the article."""

    genres: List[str] = field(default_factory=list, hash=False)
    """List of properties characterizing the content of the article, such as "PressRelease" or "UserGenerated"."""

    keywords: List[str] = field(default_factory=list, hash=False)
    """List of keywords describing the topic of the article."""

    stock_tickers: List[str] = field(default_factory=list, hash=False)
    """Comma-separated list of up to 5 stock tickers that are the main subject of the article.

    Each ticker must be prefixed by the name of its stock exchange, and must match its entry in Google Finance.
    For example, "NASDAQ:AMAT" (but not "NASD:AMAT"), or "BOM:500325" (but not "BOM:RIL")."""


@dataclass(frozen=True)
class AbstractSitemap(object, metaclass=abc.ABCMeta):
    """Abstract sitemap."""

    url: str
    """Sitemap URL."""


@dataclass(frozen=True)
class InvalidSitemap(AbstractSitemap):
    """Invalid sitemap, e.g. the one that can't be parsed."""

    reason: str
    """Reason why the sitemap is deemed invalid."""


@dataclass(frozen=True)
class StoriesSitemap(AbstractSitemap):
    """Sitemap with stories."""

    stories: List[SitemapStory]
    """Stories found in the sitemap."""


@dataclass(frozen=True)
class IndexSitemap(AbstractSitemap):
    """Sitemap with URLs to other sitemaps."""

    sub_sitemaps: List[AbstractSitemap]
    """Sub-sitemaps that are linked to from this sitemap."""


def sitemap_urls_from_robots_txt(homepage_url: str, ua: UserAgent) -> Set[str]:
    homepage_url = fix_common_url_mistakes(homepage_url)

    if not is_http_url(homepage_url):
        raise McSitemapURLsFromRobotsTxtException("URL {} is not a HTTP(s) URL.".format(homepage_url))

    try:
        homepage_url = normalize_url(homepage_url)
    except Exception as ex:
        raise McSitemapURLsFromRobotsTxtException("Unable to normalize URL {}: {}".format(homepage_url, ex))

    try:
        homepage_uri = furl(homepage_url)
    except Exception as ex:
        raise McSitemapURLsFromRobotsTxtException("Unable to parse URL {}: {}".format(homepage_url, ex))

    if not is_homepage_url(homepage_url):
        try:
            homepage_uri = homepage_uri.remove(path=True, query=True, query_params=True, fragment=True)
            log.warning("Assuming that the homepage of {} is {}".format(homepage_url, homepage_uri))
        except Exception as ex:
            raise McSitemapURLsFromRobotsTxtException(
                "Unable to determine homepage URL for URL {}: {}".format(homepage_url, ex)
            )

    robots_txt_uri = homepage_uri.copy()
    robots_txt_uri.path = '/robots.txt'

    log.info("Fetching robots.txt from {}...".format(robots_txt_uri))
    robots_txt_response = ua.get(robots_txt_uri.url)
    if not robots_txt_response.is_success():
        raise McSitemapURLsFromRobotsTxtException(
            "Unable to fetch robots.txt from {}: {}".format(robots_txt_uri, robots_txt_response.status_line())
        )

    if not robots_txt_response.content_type().lower() == 'text/plain':
        raise McSitemapURLsFromRobotsTxtException(
            "robots.txt at {} is not 'text/plain' but rather '{}'".format(
                robots_txt_uri,
                robots_txt_response.content_type(),
            )
        )

    sitemaps = set()

    for robots_txt_line in robots_txt_response.decoded_content().splitlines():
        robots_txt_line = robots_txt_line.strip()
        # robots.txt is supposed to be case sensitive but who cares in these Node.js times?
        robots_txt_line = robots_txt_line.lower()
        sitemap_match = re.search(r'^sitemap: (.+?)$', robots_txt_line, flags=re.IGNORECASE)
        if sitemap_match:
            sitemap_url = sitemap_match.group(1)
            if is_http_url(sitemap_url):
                sitemaps.add(sitemap_url)
            else:
                log.warning("Sitemap URL {} doesn't look like an URL, skipping".format(sitemap_url))

    return sitemaps


def __xml_element_name_without_namespace(element: etree.Element) -> str:
    return etree.QName(element).localname.lower()


def __sitemap_urls_from_index_sitemap(xml_root: etree.Element) -> Set[str]:
    sitemap_urls = set()

    for xml_sitemap_element in xml_root:

        xml_sitemap_element_name = __xml_element_name_without_namespace(element=xml_sitemap_element)
        if xml_sitemap_element_name != 'sitemap':
            log.warning(
                "Child element's name is not 'sitemap' but rather '{}', skipping...".format(xml_sitemap_element_name)
            )
            continue

        sitemap_url = xml_sitemap_element.findtext('{*}loc')
        if sitemap_url is None:
            log.warning("'sitemap' does not have 'loc' child, skipping...")
            continue

        if not is_http_url(sitemap_url):
            log.warning("'loc' is not a valid URL, skipping: {}".format(sitemap_url))
            continue

        sitemap_urls.add(sitemap_url)

    return sitemap_urls


class SitemapPublicationDateParser(object):
    """Fast <publication_date> parser.

    dateutil.parser.parse() is a bit slow with huge feeds, so in the class, we pre-match the date with a regex and parse
    it with a faster strptime() with a fallback to a full-blown (and slower) date parser.
    """

    # See https://support.google.com/news/publisher-center/answer/74288?hl=en for supported date formats
    __DATE_REGEXES = {

        # Complete date: YYYY-MM-DD (e.g. 1997-07-16)
        '%Y-%m-%d': re.compile(
            r'^\d\d\d\d-\d\d-\d\d$'
        ),

        # Complete date plus hours and minutes: YYYY-MM-DDThh:mmTZD (e.g. 1997-07-16T19:20+01:00)
        '%Y-%m-%dT%H:%M%z': re.compile(
            r'^\d\d\d\d-\d\d-\d\dT\d\d:\d\d[+\-]\d\d:\d\d$'
        ),

        # Complete date plus hours, minutes, and seconds: YYYY-MM-DDThh:mm:ssTZD (e.g. 1997-07-16T19:20:30+01:00)
        '%Y-%m-%dT%H:%M:%S%z': re.compile(
            r'^\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d[+\-]\d\d:\d\d$'
        ),

        # Complete date plus hours, minutes, seconds, and a decimal fraction of a second: YYYY-MM-DDThh:mm:ss.sTZD
        # (e.g. 1997-07-16T19:20:30.45+01:00)
        '%Y-%m-%dT%H:%M:%S.%s%z': re.compile(
            r'^\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d\.\d+?[+\-]\d\d:\d\d$'
        ),

    }

    @staticmethod
    def parse_sitemap_publication_date(date_string: str) -> datetime.datetime:
        """Parse <publication_date> found in sitemap."""

        if not date_string:
            raise McStoriesFromStoriesSitemapException("Date string is unset.")

        date = None

        for date_format, date_regex in SitemapPublicationDateParser.__DATE_REGEXES.items():

            if re.match(date_regex, date_string):
                date = datetime.datetime.strptime(date_string, date_format)
                break

        if date is None:
            log.warning("Parsing date of unsupported format '{}'".format(date_string))
            date = dateutil.parser.parse(date_string)

        return date


class AbstractSitemapParser(object, metaclass=abc.ABCMeta):
    """Abstract sitemap parser."""

    @abc.abstractmethod
    def __init__(self, sitemap_url: str):
        pass

    @abc.abstractmethod
    def parsed_sitemap(self) -> AbstractSitemap:
        raise NotImplementedError("Abstract method")

    @abc.abstractmethod
    def xml_start_element(self, name: str, attrs: Dict[str, str]) -> None:
        raise NotImplementedError("Abstract method")

    @abc.abstractmethod
    def xml_end_element(self, name: str) -> None:
        raise NotImplementedError("Abstract method")

    @abc.abstractmethod
    def xml_char_data(self, data: str) -> None:
        raise NotImplementedError("Abstract method")


def _html_unescape_ignore_none(string: str) -> str:
    if string:
        string = html.unescape(string)
    return string


class StoriesSitemapParser(AbstractSitemapParser):
    """Stories sitemap parser."""

    @dataclass
    class IncompleteStory(object):
        url: str = None
        title: str = None
        publish_date: str = None
        publication_name: str = None
        publication_language: str = None
        access: str = None
        genres: str = None
        keywords: str = None
        stock_tickers: str = None

        def sitemap_story(self) -> Optional[SitemapStory]:

            # Required
            url = _html_unescape_ignore_none(self.url)
            if not url:
                log.warning("URL is unset")
                return None

            title = _html_unescape_ignore_none(self.title)
            if not title:
                log.warning("Title is unset")
                return None

            publish_date = _html_unescape_ignore_none(self.publish_date)
            if not publish_date:
                log.warning("Publish date is unset")
                return None
            publish_date = SitemapPublicationDateParser.parse_sitemap_publication_date(date_string=publish_date)

            publication_name = _html_unescape_ignore_none(self.publication_name)
            if not publication_name:
                log.warning("Publication name is unset")
                return None

            publication_language = _html_unescape_ignore_none(self.publication_language)
            if not publication_language:
                log.warning("Publication language is unset")
                return None

            # Optional
            access = _html_unescape_ignore_none(self.access)

            genres = _html_unescape_ignore_none(self.genres)
            if genres:
                genres = [html.unescape(x.strip()) for x in genres.split(',')]

            keywords = _html_unescape_ignore_none(self.keywords)
            if keywords:
                keywords = [html.unescape(x.strip()) for x in keywords.split(',')]

            stock_tickers = _html_unescape_ignore_none(self.stock_tickers)
            if stock_tickers:
                stock_tickers = [html.unescape(x.strip()) for x in stock_tickers.split(',')]

            return SitemapStory(
                url=url,
                title=title,
                publish_date=publish_date,
                publication_name=publication_name,
                publication_language=publication_language,
                access=access,
                genres=genres,
                keywords=keywords,
                stock_tickers=stock_tickers,
            )

    __slots__ = [
        # Sitemap URL
        '__sitemap_url',

        # Stories parsed from the sitemap
        '__stories',

        # Story that is being created while parsing
        '__incomplete_story',

        # Last encountered character data
        '__last_char_data',
    ]

    def __init__(self, sitemap_url: str):
        super().__init__(sitemap_url=sitemap_url)

        self.__sitemap_url = sitemap_url
        self.__stories = []
        self.__incomplete_story = None
        self.__last_char_data = None

    def parsed_sitemap(self) -> StoriesSitemap:
        return StoriesSitemap(
            url=self.__sitemap_url,
            stories=self.__stories,
        )

    def xml_start_element(self, name: str, attrs: Dict[str, str]) -> None:

        if name == 'url':
            if self.__incomplete_story:
                raise McSitemapParserException("Story is expected to be unset by <url>.")
            self.__incomplete_story = StoriesSitemapParser.IncompleteStory()

    def xml_end_element(self, name: str) -> None:

        if name == 'url':
            if not self.__incomplete_story:
                raise McSitemapParserException("Story is expected to be set by </url>.")

            story = self.__incomplete_story.sitemap_story()
            if story:
                self.__stories.append(story)

            self.__incomplete_story = None

        elif name == 'loc':
            if not self.__incomplete_story:
                raise McSitemapParserException("Story is expected to be set by </loc>.")

            if not self.__last_char_data:
                raise McSitemapParserException("Character data should have been encountered by </loc>.")

            self.__incomplete_story.url = self.__last_char_data

        elif name == 'name':  # news/publication/name
            if not self.__incomplete_story:
                raise McSitemapParserException("Story is expected to be set by </news:name>.")

            if not self.__last_char_data:
                raise McSitemapParserException("Character data should have been encountered by </news:name>.")

            self.__incomplete_story.publication_name = self.__last_char_data

        elif name == 'language':  # news/publication/language
            if not self.__incomplete_story:
                raise McSitemapParserException("Story is expected to be set by </news:language>.")

            if not self.__last_char_data:
                raise McSitemapParserException("Character data should have been encountered by </news:language>.")

            self.__incomplete_story.publication_language = self.__last_char_data

        elif name == 'publication_date':
            if not self.__incomplete_story:
                raise McSitemapParserException("Story is expected to be set by </news:publication_date>.")

            if not self.__last_char_data:
                raise McSitemapParserException(
                    "Character data should have been encountered by </news:publication_date>."
                )

            self.__incomplete_story.publish_date = self.__last_char_data

        elif name == 'title':
            if not self.__incomplete_story:
                raise McSitemapParserException("Story is expected to be set by </news:title>.")

            if not self.__last_char_data:
                raise McSitemapParserException("Character data should have been encountered by </news:title>.")

            self.__incomplete_story.title = self.__last_char_data

        elif name == 'access':
            if not self.__incomplete_story:
                raise McSitemapParserException("Story is expected to be set by </news:access>.")

            if not self.__last_char_data:
                raise McSitemapParserException("Character data should have been encountered by </news:access>.")

            self.__incomplete_story.access = self.__last_char_data

        elif name == 'keywords':
            if not self.__incomplete_story:
                raise McSitemapParserException("Story is expected to be set by </news:keywords>.")

            if not self.__last_char_data:
                raise McSitemapParserException("Character data should have been encountered by </news:keywords>.")

            self.__incomplete_story.keywords = self.__last_char_data

        elif name == 'stock_tickers':
            if not self.__incomplete_story:
                raise McSitemapParserException("Story is expected to be set by </news:stock_tickers>.")

            if not self.__last_char_data:
                raise McSitemapParserException("Character data should have been encountered by </news:stock_tickers>.")

            self.__incomplete_story.stock_tickers = self.__last_char_data

        else:
            log.warning("Unknown element: {}".format(name))

        # End of any element always resets last encountered character data
        self.__last_char_data = None

    def xml_char_data(self, data: str) -> None:
        self.__last_char_data = data


class IndexSitemapParser(AbstractSitemapParser):
    """Index sitemap parser."""

    @dataclass
    class IncompleteSubSitemap(object):
        url: str = None
        last_modified: str = None

        def sub_sitemap(self) -> Optional[List[AbstractSitemap]]:

            # Required
            url = _html_unescape_ignore_none(self.url)
            if not url:
                log.warning("URL is unset")
                return None

            title = _html_unescape_ignore_none(self.title)
            if not title:
                log.warning("Title is unset")
                return None

            publish_date = _html_unescape_ignore_none(self.publish_date)
            if not publish_date:
                log.warning("Publish date is unset")
                return None
            publish_date = SitemapPublicationDateParser.parse_sitemap_publication_date(date_string=publish_date)

            publication_name = _html_unescape_ignore_none(self.publication_name)
            if not publication_name:
                log.warning("Publication name is unset")
                return None

            publication_language = _html_unescape_ignore_none(self.publication_language)
            if not publication_language:
                log.warning("Publication language is unset")
                return None

            # Optional
            access = _html_unescape_ignore_none(self.access)

            genres = _html_unescape_ignore_none(self.genres)
            if genres:
                genres = [html.unescape(x.strip()) for x in genres.split(',')]

            keywords = _html_unescape_ignore_none(self.keywords)
            if keywords:
                keywords = [html.unescape(x.strip()) for x in keywords.split(',')]

            stock_tickers = _html_unescape_ignore_none(self.stock_tickers)
            if stock_tickers:
                stock_tickers = [html.unescape(x.strip()) for x in stock_tickers.split(',')]

            return SitemapStory(
                url=url,
                title=title,
                publish_date=publish_date,
                publication_name=publication_name,
                publication_language=publication_language,
                access=access,
                genres=genres,
                keywords=keywords,
                stock_tickers=stock_tickers,
            )

    __slots__ = [
        # Sitemap URL
        '__sitemap_url',

        # Sub-sitemaps parsed from a sitemap
        '__sub_sitemaps',

        # Sub-sitemap that is being created while parsing
        '__incomplete_sub_sitemap',

        # Last encountered character data
        '__last_char_data',
    ]

    def __init__(self, sitemap_url: str):
        super().__init__(sitemap_url=sitemap_url)

        self.__sitemap_url = sitemap_url
        self.__sub_sitemaps = []
        self.__incomplete_sub_sitemap = None
        self.__last_char_data = None



class McSitemapParserException(Exception):
    pass


class SitemapFetcherAndParser(AbstractSitemapParser):
    """Generic sitemap parser which decides which specialized parser (stories or index) to use."""

    __slots__ = [
        '__sitemap_url',
        '__sitemap_parser',
        '__sitemap',
    ]

    # Sitemaps might get heavy
    __MAX_SITEMAP_SIZE = 100 * 1024 * 1024

    # Max. recursion level in iterating over sub-sitemaps
    __MAX_SITEMAP_RECURSION_LEVEL = 10

    def __init__(self, sitemap_url: str, recursion_level: int = 0):
        super().__init__(sitemap_url=sitemap_url)

        if recursion_level > self.__MAX_SITEMAP_RECURSION_LEVEL:
            log.error("Reached max. recursion level of {}; returning empty story URLs list for sitemap URL {}".format(
                self.__MAX_SITEMAP_RECURSION_LEVEL, sitemap_url,
            ))

        self.__sitemap_url = sitemap_url
        self.__sitemap_parser = None

        try:
            sitemap_xml = self.__fetch_sitemap()
            self.__sitemap = self.__parse_sitemap(sitemap_xml)
        except Exception as ex:
            reason = "Unable to fetch / parse sitemap from URL {}: {}".format(sitemap_url, ex)
            log.error(reason)
            self.__sitemap = InvalidSitemap(url=self.__sitemap_url, reason=reason)

    def __fetch_sitemap(self) -> str:
        log.info("Fetching sitemap URL {}...".format(self.__sitemap_url))
        ua = UserAgent()
        ua.set_max_size(SitemapFetcherAndParser.__MAX_SITEMAP_SIZE)
        sitemap_response = ua.get(self.__sitemap_url)
        if not sitemap_response.is_success():
            raise McSitemapParserException(
                "Unable to fetch sitemap from {}: {}".format(self.__sitemap_url, sitemap_response.status_line())
            )
        return sitemap_response.decoded_content()

    def __parse_sitemap(self, sitemap_xml) -> AbstractSitemap:
        parser = xml.parsers.expat.ParserCreate()
        parser.StartElementHandler = self.xml_start_element
        parser.EndElementHandler = self.xml_end_element
        parser.CharacterDataHandler = self.xml_char_data

        log.info("Parsing sitemap from URL {}...".format(self.__sitemap_url))
        parser.Parse(data=sitemap_xml, isfinal=True)

    def parsed_sitemap(self) -> AbstractSitemap:
        assert self.__sitemap, "Sitemap should be set at this point."
        return self.__sitemap

    def xml_start_element(self, name: str, attrs: Dict[str, str]) -> None:
        if self.__sitemap_parser is None:
            if name == 'urlset':
                # Stories sitemap
                self.__sitemap_parser = StoriesSitemapParser(sitemap_url=self.__sitemap_url)
            elif name == 'sitemapindex':
                # Index sitemap
                self.__sitemap_parser = IndexSitemapParser(sitemap_url=self.__sitemap_url)
            else:
                raise McSitemapParserException(
                    "Sitemap from URL {} has unsupported root element '{}'.".format(self.__sitemap_url, name)
                )

        assert self.__sitemap_parser, "Sitemap parser should be set at this point."

        self.__sitemap_parser.xml_start_element(name=name, attrs=attrs)

    def xml_end_element(self, name: str) -> None:
        assert self.__sitemap_parser, "Sitemap parser should be set at this point."

        self.__sitemap_parser.xml_end_element(name=name)

    def xml_char_data(self, data: str) -> None:
        assert self.__sitemap_parser, "Sitemap parser should be set at this point."

        self.__sitemap_parser.xml_char_data(data=data)


def __stories_from_stories_sitemap(xml_root: etree.Element) -> List[SitemapStory]:
    stories = []

    for xml_url_element in xml_root:

        story_url = xml_url_element.findtext('{*}loc')
        if story_url is None:
            log.warning("'url' does not have 'loc' child, skipping...")
            continue

        # is_http_url() might work here but it's rather slow, so we'll trust code that fetches the URLs to do validation

        xml_news_element = xml_url_element.find('{*}news')
        if xml_news_element is None:
            # debug() because there's going to be plenty of those (most of sitemaps have nothing to do with news)
            log.debug("'url' does not have 'news' child, skipping...")
            continue

        story_date = xml_news_element.findtext('{*}publication_date')
        if story_date is None:
            log.warning("'news' does not have 'publication_date' child, skipping...")
            continue
        try:
            story_date = SitemapPublicationDateParser.parse_sitemap_publication_date(date_string=story_date)
        except Exception as ex:
            log.warning("Unable to parse publication date '{}', skipping: {}".format(story_date, ex))
            continue

        story_title = xml_news_element.findtext('{*}title')
        if story_title is None:
            log.warning("'news' does not have 'title' child, skipping...")
            continue
        story_title = html.unescape(story_title)

        story_access = xml_news_element.findtext('{*}access')
        if story_access:
            story_access = html.unescape(story_access)

        story_genres = xml_news_element.findtext('{*}genres')
        if story_genres:
            story_genres = [html.unescape(x.strip()) for x in story_genres.split(',')]
        else:
            story_genres = []

        story_keywords = xml_news_element.findtext('{*}keywords')
        if story_keywords:
            story_keywords = [html.unescape(x.strip()) for x in story_keywords.split(',')]
        else:
            story_keywords = []

        story_stock_tickers = xml_news_element.findtext('{*}stock_tickers')
        if story_stock_tickers:
            story_stock_tickers = [html.unescape(x.strip()) for x in story_stock_tickers.split(',')]
        else:
            story_stock_tickers = []

        xml_publication_element = xml_news_element.find('{*}publication')
        if xml_publication_element is None:
            log.warning("'news' does not have 'publication' child, skipping...")
            continue

        story_publication_name = xml_publication_element.findtext('{*}name')
        if story_publication_name is None:
            log.warning("'publication' does not have 'name' child, skipping...")
            continue
        story_publication_name = html.unescape(story_publication_name)

        story_publication_language = xml_publication_element.findtext('{*}language')
        if story_publication_language is None:
            log.warning("'publication' does not have 'language' child, skipping...")
            continue
        story_publication_language = html.unescape(story_publication_language)

        story = SitemapStory(
            url=story_url,
            title=story_title,
            date=story_date,
            publication=SitemapStoryPublication(
                name=story_publication_name,
                language=story_publication_language,
            ),
            access=story_access,
            genres=story_genres,
            keywords=story_keywords,
            stock_tickers=story_stock_tickers,
        )

        stories.append(story)

    return stories


def sitemap_from_url(sitemap_url: str, ua: UserAgent, recursion_level: int = 0) -> AbstractSitemap:
    # Not testing MIME type because a misconfigured server might return funky stuff; instead, rely on XML parser

    log.info("Parsing sitemap URL {}...".format(sitemap_url))
    try:
        xml_root = etree.fromstring(sitemap_response.decoded_content().encode('utf-8'))
    except Exception as ex:
        log.warning("Unable to parse sitemap from URL {}, returning empty story URLs list: {}".format(sitemap_url, ex))
        sitemap = InvalidSitemap(url=sitemap_url)

    else:

        xml_root_element_name = __xml_element_name_without_namespace(element=xml_root)
        if xml_root_element_name == 'urlset':
            # Stories sitemap
            log.info("Collecting stories from sitemap URL {}...".format(sitemap_url))
            sitemap_stories = __stories_from_stories_sitemap(xml_root=xml_root)
            sitemap = StoriesSitemap(
                url=sitemap_url,
                stories=sitemap_stories,
            )

        elif xml_root_element_name == 'sitemapindex':
            # Sitemap index

            log.info("Collecting sub-sitemaps from sitemap URL {}...".format(sitemap_url))
            try:
                sub_sitemap_urls = __sitemap_urls_from_index_sitemap(xml_root=xml_root)
            except Exception as ex:
                log.error("Unable to get sub-sitemap URLs from sitemap URL {}: {}".format(sitemap_url, ex))
                sitemap = InvalidSitemap(url=sitemap_url)
            else:
                sub_sitemaps = []
                for sub_sitemap_url in sub_sitemap_urls:
                    sub_sitemap = sitemap_from_url(
                        sitemap_url=sub_sitemap_url,
                        ua=ua,
                        recursion_level=recursion_level + 1,
                    )
                    sub_sitemaps.append(sub_sitemap)
                sitemap = IndexSitemap(
                    url=sitemap_url,
                    sub_sitemaps=sub_sitemaps,
                )

        else:
            log.warning(
                "Sitemap from URL {} contains unsupported root element '{}', returning empty story URLs list".format(
                    sitemap_url, xml_root_element_name,
                )
            )
            sitemap = InvalidSitemap(url=sitemap_url)

    log.info("Done parsing sitemap URL {}.".format(sitemap_url))

    return sitemap


def homepage_sitemaps(homepage_url: str, ua: UserAgent) -> List[AbstractSitemap]:
    sitemaps = []

    root_sitemap_urls = sitemap_urls_from_robots_txt(homepage_url=homepage_url, ua=ua)
    for sitemap_url in root_sitemap_urls:
        sitemap = sitemap_from_url(sitemap_url=sitemap_url, ua=ua)
        sitemaps.append(sitemap)

    return sitemaps


def __sitemap_useragent() -> UserAgent:
    ua = UserAgent()
    ua.set_max_size(MAX_SITEMAP_SIZE)
    return ua


if __name__ == "__main__":
    retrieved_sitemaps = homepage_sitemaps(homepage_url='https://www.15min.lt///', ua=__sitemap_useragent())
    print("Sitemaps: {}".format(retrieved_sitemaps))
    # test_sitemap = sitemap_from_url(
    #     sitemap_url='http://localhost:8000/15min_sitemap_sample.xml',
    #     ua=__sitemap_useragent(),
    # )
    # print(test_sitemap)
