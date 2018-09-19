#!/usr/bin/env python3

"""Sitemap feed evaluation."""

# FIXME Gzipped sitemaps
# FIXME namespace handling
# FIXME asyncio
import abc
import datetime
import html
import re
from typing import Set, List

import dateutil
from furl import furl
from lxml import etree

from mediawords.util.log import create_logger
from mediawords.util.url import normalize_url, is_homepage_url, fix_common_url_mistakes, is_http_url
from mediawords.util.web.user_agent import UserAgent

log = create_logger(__name__)

# Sitemaps might get heavy
MAX_SITEMAP_SIZE = 100 * 1024 * 1024

# Max. recursion level in iterating over sub-sitemaps
MAX_SITEMAP_RECURSION_LEVEL = 10


class McSitemapURLsFromRobotsTxtException(Exception):
    pass


class McStoriesFromStoriesSitemapException(Exception):
    pass


class SitemapStoryPublication(object):
    """Publication of the story."""

    __slots__ = [
        # Name of the news publication
        '__name',

        # Language of the publication
        # (it should be an ISO 639 Language Code (either 2 or 3 letters))
        '__language',
    ]

    def __init__(self, name: str, language: str):
        self.__name = name
        self.__language = language

    def name(self) -> str:
        return self.__name

    def language(self) -> str:
        return self.__language


class SitemapStory(object):
    """Single sitemap-derived story."""

    __slots__ = [
        # Story URL
        '__url',

        # Story title
        '__title',

        # Story publication date
        '__date',

        # Publication in which the article appears
        '__publication',

        # Accessibility of the article
        '__access',

        # List of properties characterizing the content of the article, such as "PressRelease" or "UserGenerated"
        '__genres',

        # List of keywords describing the topic of the article
        '__keywords',

        # Comma-separated list of up to 5 stock tickers that are the main subject of the article.
        #
        # Each ticker must be prefixed by the name of its stock exchange, and must match its entry in Google Finance.
        # For example, "NASDAQ:AMAT" (but not "NASD:AMAT"), or "BOM:500325" (but not "BOM:RIL").
        '__stock_tickers',
    ]

    def __init__(self,
                 url: str,
                 title: str,
                 date: datetime.datetime,
                 publication: SitemapStoryPublication,
                 access: str = None,
                 genres: List[str] = None,
                 keywords: List[str] = None,
                 stock_tickers: List[str] = None):
        self.__url = url
        self.__title = title
        self.__date = date
        self.__publication = publication
        self.__access = access
        self.__genres = genres if genres else []
        self.__keywords = keywords if keywords else []
        self.__stock_tickers = stock_tickers if stock_tickers else []

    def __hash__(self):
        return hash(self.__url)


class AbstractSitemap(object, metaclass=abc.ABCMeta):
    """Abstract sitemap."""

    __slots__ = [
        # Sitemap URL
        '__url',
    ]

    def __init__(self, url: str):
        self.__url = url

    def url(self) -> str:
        return self.__url

    def __hash__(self):
        return hash(self.__url)


class InvalidSitemap(AbstractSitemap):
    """Invalid sitemap, e.g. the one that can't be parsed."""
    pass


class StoriesSitemap(AbstractSitemap):
    """Sitemap with stories."""

    __slots__ = [
        # Stories found in the sitemap
        '__stories',
    ]

    def __init__(self, url: str, stories: List[SitemapStory]):
        super().__init__(url=url)
        self.__stories = stories

    def stories(self) -> List[SitemapStory]:
        return self.__stories


class IndexSitemap(AbstractSitemap):
    """Sitemap with URLs to other sitemaps."""

    __slots__ = [
        # Sub-sitemaps that are linked to from this sitemap
        '__sub_sitemaps',
    ]

    def __init__(self, url: str, sub_sitemaps: List[AbstractSitemap]):
        super().__init__(url=url)
        self.__sub_sitemaps = sub_sitemaps

    def sub_sitemaps(self) -> List[AbstractSitemap]:
        return self.__sub_sitemaps


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


def __stories_from_stories_sitemap(xml_root: etree.Element) -> List[SitemapStory]:
    stories = []

    for xml_url_element in xml_root:

        xml_url_element_name = __xml_element_name_without_namespace(element=xml_url_element)
        if xml_url_element_name != 'url':
            log.warning(
                "Child element's name is not 'url' but rather '{}', skipping...".format(xml_url_element_name)
            )
            continue

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
    if recursion_level > MAX_SITEMAP_RECURSION_LEVEL:
        log.error("Reached max. recursion level of {}; returning empty story URLs list for sitemap URL {}".format(
            MAX_SITEMAP_RECURSION_LEVEL, sitemap_url,
        ))

    log.info("Fetching sitemap URL {}...".format(sitemap_url))
    sitemap_response = ua.get(sitemap_url)
    if not sitemap_response.is_success():
        raise McStoriesFromStoriesSitemapException(
            "Unable to fetch sitemap from {}: {}".format(sitemap_url, sitemap_response.status_line())
        )

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
    # retrieved_sitemaps = homepage_sitemaps(homepage_url='https://www.15min.lt///', ua=__sitemap_useragent())
    # print("Sitemaps: {}".format(retrieved_sitemaps))
    test_sitemap = sitemap_from_url(
        sitemap_url='http://localhost:8000/15min_sitemap_sample.xml',
        ua=__sitemap_useragent(),
    )
    print(test_sitemap)
