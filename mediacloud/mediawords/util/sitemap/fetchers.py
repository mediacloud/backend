import abc
import re
import xml.parsers.expat
from dataclasses import field, dataclass
from decimal import Decimal
from typing import Optional, Dict

from furl import furl

from mediawords.util.log import create_logger
from mediawords.util.url import fix_common_url_mistakes, is_http_url, normalize_url, is_homepage_url
from mediawords.util.web.user_agent import UserAgent
from mediawords.util.sitemap.exceptions import McSitemapsException, McSitemapsXMLParsingException
from mediawords.util.sitemap.helpers import (
    sitemap_useragent,
    html_unescape_strip,
    parse_sitemap_publication_date,
    get_url_retry_on_client_errors,
    ungzipped_response_content,
)
from mediawords.util.sitemap.objects import (
    AbstractSitemap,
    InvalidSitemap,
    IndexRobotsTxtSitemap,
    IndexXMLSitemap,
    SitemapPage,
    PagesXMLSitemap,
    SitemapPageChangeFrequency,
    SitemapNewsStory,
    SITEMAP_PAGE_DEFAULT_PRIORITY,
)

log = create_logger(__name__)


class AbstractSitemapFetcher(object, metaclass=abc.ABCMeta):
    """Abstract sitemap fetcher."""

    # Max. recursion level in iterating over sub-sitemaps
    __MAX_RECURSION_LEVEL = 10

    __slots__ = [
        '_recursion_level',
        '_uri',  # furl object
        '_ua',  # UserAgent object
    ]

    def __init__(self, url: str, recursion_level: int, ua: Optional[UserAgent] = None):

        if recursion_level > self.__MAX_RECURSION_LEVEL:
            raise McSitemapsException("Recursion level exceeded {} for URL {}.".format(self.__MAX_RECURSION_LEVEL, url))

        url = fix_common_url_mistakes(url)

        if not is_http_url(url):
            raise McSitemapsException("URL {} is not a HTTP(s) URL.".format(url))

        try:
            url = normalize_url(url)
        except Exception as ex:
            raise McSitemapsException("Unable to normalize URL {}: {}".format(url, ex))

        try:
            uri = furl(url)
        except Exception as ex:
            raise McSitemapsException("Unable to parse URL {}: {}".format(url, ex))

        if not ua:
            ua = sitemap_useragent()

        self._uri = uri
        self._ua = ua
        self._recursion_level = recursion_level

    @abc.abstractmethod
    def sitemap(self) -> AbstractSitemap:
        raise NotImplementedError("Abstract method")


class IndexRobotsTxtSitemapFetcher(AbstractSitemapFetcher):
    """robots.txt index sitemap fetcher."""

    def __init__(self, homepage_url: str, ua: Optional[UserAgent] = None):

        super().__init__(url=homepage_url, recursion_level=0, ua=ua)

        if not is_homepage_url(str(self._uri.url)):
            try:
                self._uri = self._uri.remove(path=True, query=True, query_params=True, fragment=True)
                log.warning("Assuming that the homepage of {} is {}".format(homepage_url, self._uri))
            except Exception as ex:
                raise McSitemapsException("Unable to determine homepage URL for URL {}: {}".format(homepage_url, ex))

    def sitemap(self) -> AbstractSitemap:
        robots_txt_uri = self._uri.copy()
        robots_txt_uri.path = '/robots.txt'

        log.info("Fetching robots.txt from {}...".format(robots_txt_uri))
        robots_txt_response = get_url_retry_on_client_errors(url=str(robots_txt_uri.url), ua=self._ua)
        if not robots_txt_response.is_success():
            # noinspection PyArgumentList
            return InvalidSitemap(
                url=str(robots_txt_uri.url),
                reason="Unable to fetch robots.txt from {}: {}".format(
                    robots_txt_uri,
                    robots_txt_response.status_line(),
                ),
            )

        if not robots_txt_response.content_type().lower() == 'text/plain':
            # noinspection PyArgumentList
            return InvalidSitemap(
                url=str(robots_txt_uri.url),
                reason="robots.txt at {} is not 'text/plain' but rather '{}'".format(
                    robots_txt_uri,
                    robots_txt_response.content_type(),
                ),
            )

        sitemap_urls = []

        for robots_txt_line in robots_txt_response.decoded_content().splitlines():
            robots_txt_line = robots_txt_line.strip()
            # robots.txt is supposed to be case sensitive but who cares in these Node.js times?
            robots_txt_line = robots_txt_line.lower()
            sitemap_match = re.search(r'^sitemap: (.+?)$', robots_txt_line, flags=re.IGNORECASE)
            if sitemap_match:
                sitemap_url = sitemap_match.group(1)
                if is_http_url(sitemap_url):
                    if sitemap_url not in sitemap_urls:
                        sitemap_urls.append(sitemap_url)
                else:
                    log.warning("Sitemap URL {} doesn't look like an URL, skipping".format(sitemap_url))

        sub_sitemaps = []

        for sitemap_url in sitemap_urls:
            fetcher = XMLSitemapFetcher(url=sitemap_url, recursion_level=0, ua=self._ua)
            fetched_sitemap = fetcher.sitemap()
            sub_sitemaps.append(fetched_sitemap)

        # noinspection PyArgumentList
        index_sitemap = IndexRobotsTxtSitemap(url=str(robots_txt_uri.url), sub_sitemaps=sub_sitemaps)

        return index_sitemap


class XMLSitemapFetcher(AbstractSitemapFetcher):
    """XML sitemap fetcher."""

    __XML_NAMESPACE_SEPARATOR = ' '

    __slots__ = [
        '_sitemap_parser',
    ]

    def __init__(self, url: str, recursion_level: int, ua: UserAgent):
        super().__init__(url=url, recursion_level=recursion_level, ua=ua)

        # Will be initialized when the type of sitemap is known
        self._sitemap_parser = None

    def sitemap(self) -> AbstractSitemap:

        sitemap_response = get_url_retry_on_client_errors(url=str(self._uri.url), ua=self._ua)
        if not sitemap_response.is_success():
            # noinspection PyArgumentList
            return InvalidSitemap(
                url=str(self._uri.url),
                reason="Unable to fetch sitemap from {}: {}".format(str(self._uri.url), sitemap_response.status_line()),
            )

        sitemap_xml = ungzipped_response_content(sitemap_response)

        parser = xml.parsers.expat.ParserCreate(namespace_separator=self.__XML_NAMESPACE_SEPARATOR)
        parser.StartElementHandler = self._xml_element_start
        parser.EndElementHandler = self._xml_element_end
        parser.CharacterDataHandler = self._xml_char_data

        log.info("Parsing sitemap from URL {}...".format(self._uri.url))
        try:
            is_final = True
            parser.Parse(sitemap_xml, is_final)
        except Exception as ex:
            # Some sitemap XML files might end abruptly because webservers might be timing out on returning huge XML
            # files so don't return InvalidSitemap() but try to get as much pages as possible
            log.error("Parsing sitemap from URL {} failed: {}".format(self._uri.url, ex))

        if not self._sitemap_parser:
            # noinspection PyArgumentList
            return InvalidSitemap(
                url=str(self._uri.url),
                reason="No parsers support sitemap from {}".format(self._uri.url),
            )

        return self._sitemap_parser.sitemap()

    @classmethod
    def __normalize_xml_element_name(cls, name: str):
        """Replace the namespace URL in the argument element name with internal namespace.

        * Elements from http://www.sitemaps.org/schemas/sitemap/0.9 namespace will be prefixed with "sitemap:",
          e.g. "<loc>" will become "<sitemap:loc>"

        * Elements from http://www.google.com/schemas/sitemap-news/0.9 namespace will be prefixed with "news:",
          e.g. "<publication>" will become "<news:publication>"

        For non-sitemap namespaces, return the element name with the namespace stripped."""

        name_parts = name.split(cls.__XML_NAMESPACE_SEPARATOR)

        if len(name_parts) == 1:
            namespace_url = ''
            name = name_parts[0]

        elif len(name_parts) == 2:
            namespace_url = name_parts[0]
            name = name_parts[1]

        else:
            raise McSitemapsXMLParsingException("Unable to determine namespace for element '{}'".format(name))

        if '/sitemap/' in namespace_url:
            name = 'sitemap:{}'.format(name)
        elif '/sitemap-news/' in namespace_url:
            name = 'news:{}'.format(name)
        else:
            # We don't care about the rest of the namespaces, so just keep the plain element name
            pass

        return name

    def _xml_element_start(self, name: str, attrs: Dict[str, str]) -> None:

        name = self.__normalize_xml_element_name(name)

        if self._sitemap_parser:
            self._sitemap_parser.xml_element_start(name=name, attrs=attrs)

        else:

            # Root element -- initialize concrete parser
            if name == 'sitemap:urlset':
                self._sitemap_parser = PagesXMLSitemapParser(
                    url=str(self._uri.url),
                )

            elif name == 'sitemap:sitemapindex':
                self._sitemap_parser = IndexXMLSitemapParser(
                    url=str(self._uri.url),
                    ua=self._ua,
                    recursion_level=self._recursion_level,
                )
            else:
                raise McSitemapsXMLParsingException("Unsupported root element '{}'.".format(name))

    def _xml_element_end(self, name: str) -> None:

        name = self.__normalize_xml_element_name(name)

        if not self._sitemap_parser:
            raise McSitemapsXMLParsingException("Concrete sitemap parser should be set by now.")

        self._sitemap_parser.xml_element_end(name=name)

    def _xml_char_data(self, data: str) -> None:

        if not self._sitemap_parser:
            raise McSitemapsXMLParsingException("Concrete sitemap parser should be set by now.")

        self._sitemap_parser.xml_char_data(data=data)


class AbstractXMLSitemapParser(object, metaclass=abc.ABCMeta):
    """Abstract XML sitemap parser."""

    __slots__ = [
        # URL of the sitemap that is being parsed
        '_url',

        # Last encountered character data
        '_last_char_data',

        '_last_handler_call_was_xml_char_data',
    ]

    def __init__(self, url: str):
        self._url = url
        self._last_char_data = ''
        self._last_handler_call_was_xml_char_data = False

    def xml_element_start(self, name: str, attrs: Dict[str, str]) -> None:
        self._last_handler_call_was_xml_char_data = False
        pass

    def xml_element_end(self, name: str) -> None:
        # End of any element always resets last encountered character data
        self._last_char_data = ''
        self._last_handler_call_was_xml_char_data = False

    def xml_char_data(self, data: str) -> None:
        # Handler might be called multiple times for what essentially is a single string, e.g. in case of entities
        # ("ABC &amp; DEF"), so this is why we're appending
        if self._last_handler_call_was_xml_char_data:
            self._last_char_data += data
        else:
            self._last_char_data = data

        self._last_handler_call_was_xml_char_data = True

    @abc.abstractmethod
    def sitemap(self) -> AbstractSitemap:
        raise NotImplementedError("Abstract method.")


class IndexXMLSitemapParser(AbstractXMLSitemapParser):
    """Index XML sitemap parser."""

    __slots__ = [
        '_ua',
        '_recursion_level',

        # List of sub-sitemap URLs found in this index sitemap
        '_sub_sitemap_urls',
    ]

    def __init__(self, url: str, ua: UserAgent, recursion_level: int):
        super().__init__(url=url)

        self._ua = ua
        self._recursion_level = recursion_level
        self._sub_sitemap_urls = []

    def xml_element_end(self, name: str) -> None:

        if name == 'sitemap:loc':
            sub_sitemap_url = html_unescape_strip(self._last_char_data)
            if not is_http_url(sub_sitemap_url):
                log.warning("Sub-sitemap URL does not look like one: {}".format(sub_sitemap_url))

            else:
                if sub_sitemap_url not in self._sub_sitemap_urls:
                    self._sub_sitemap_urls.append(sub_sitemap_url)

        super().xml_element_end(name=name)

    def sitemap(self) -> AbstractSitemap:

        sub_sitemaps = []

        for sub_sitemap_url in self._sub_sitemap_urls:

            # URL might be invalid, or recursion limit might have been reached
            try:
                fetcher = XMLSitemapFetcher(url=sub_sitemap_url,
                                            recursion_level=self._recursion_level + 1,
                                            ua=self._ua)
                fetched_sitemap = fetcher.sitemap()
            except Exception as ex:
                # noinspection PyArgumentList
                fetched_sitemap = InvalidSitemap(
                    url=sub_sitemap_url,
                    reason="Unable to add sub-sitemap from URL {}: {}".format(sub_sitemap_url, str(ex)),
                )

            sub_sitemaps.append(fetched_sitemap)

        # noinspection PyArgumentList
        index_sitemap = IndexXMLSitemap(url=self._url, sub_sitemaps=sub_sitemaps)

        return index_sitemap


class PagesXMLSitemapParser(AbstractXMLSitemapParser):
    """Pages XML sitemap parser."""

    @dataclass(unsafe_hash=True)
    class Page(object):
        """Simple data class for holding various properties for a single <url> entry while parsing."""
        url: str = field(default=None, hash=True)
        last_modified: str = None
        change_frequency: str = None
        priority: str = None
        news_title: str = None
        news_publish_date: str = None
        news_publication_name: str = None
        news_publication_language: str = None
        news_access: str = None
        news_genres: str = None
        news_keywords: str = None
        news_stock_tickers: str = None

        def page(self) -> Optional[SitemapPage]:
            """Return constructed sitemap page if one has been completed, otherwise None."""

            # Required
            url = html_unescape_strip(self.url)
            if not url:
                log.error("URL is unset")
                return None

            try:
                url = normalize_url(url)
            except Exception as ex:
                log.error("Unable to normalize URL {}: {}".format(url, ex))
                return None

            last_modified = html_unescape_strip(self.last_modified)
            if last_modified:
                last_modified = parse_sitemap_publication_date(last_modified)

            change_frequency = html_unescape_strip(self.change_frequency)
            if change_frequency:
                change_frequency = SitemapPageChangeFrequency(change_frequency.lower())
                assert isinstance(change_frequency, SitemapPageChangeFrequency)

            priority = html_unescape_strip(self.priority)
            if priority:
                priority = Decimal(priority)

                comp_zero = priority.compare(Decimal('0.0'))
                comp_one = priority.compare(Decimal('1.0'))
                if comp_zero in (Decimal('0'), Decimal('1') and comp_one in (Decimal('0'), Decimal('-1'))):
                    # 0 <= priority <= 1
                    pass
                else:
                    log.warning("Priority is not within 0 and 1: {}".format(priority))
                    priority = SITEMAP_PAGE_DEFAULT_PRIORITY

            else:
                priority = SITEMAP_PAGE_DEFAULT_PRIORITY

            news_title = html_unescape_strip(self.news_title)

            news_publish_date = html_unescape_strip(self.news_publish_date)
            if news_publish_date:
                news_publish_date = parse_sitemap_publication_date(date_string=news_publish_date)

            news_publication_name = html_unescape_strip(self.news_publication_name)
            news_publication_language = html_unescape_strip(self.news_publication_language)
            news_access = html_unescape_strip(self.news_access)

            news_genres = html_unescape_strip(self.news_genres)
            if news_genres:
                news_genres = [x.strip() for x in news_genres.split(',')]
            else:
                news_genres = []

            news_keywords = html_unescape_strip(self.news_keywords)
            if news_keywords:
                news_keywords = [x.strip() for x in news_keywords.split(',')]
            else:
                news_keywords = []

            news_stock_tickers = html_unescape_strip(self.news_stock_tickers)
            if news_stock_tickers:
                news_stock_tickers = [x.strip() for x in news_stock_tickers.split(',')]
            else:
                news_stock_tickers = []

            sitemap_news_story = None
            if news_title and news_publish_date:
                sitemap_news_story = SitemapNewsStory(
                    title=news_title,
                    publish_date=news_publish_date,
                    publication_name=news_publication_name,
                    publication_language=news_publication_language,
                    access=news_access,
                    genres=news_genres,
                    keywords=news_keywords,
                    stock_tickers=news_stock_tickers,
                )

            return SitemapPage(
                url=url,
                last_modified=last_modified,
                change_frequency=change_frequency,
                priority=priority,
                news_story=sitemap_news_story,
            )

    __slots__ = [
        '_current_page',
        '_pages',
    ]

    def __init__(self, url: str):
        super().__init__(url=url)

        self._current_page = None
        self._pages = []

    def xml_element_start(self, name: str, attrs: Dict[str, str]) -> None:

        super().xml_element_start(name=name, attrs=attrs)

        if name == 'sitemap:url':
            if self._current_page:
                raise McSitemapsXMLParsingException("Page is expected to be unset by <url>.")
            self._current_page = self.Page()

    def __require_last_char_data_to_be_set(self, name: str) -> None:
        if not self._last_char_data:
            raise McSitemapsXMLParsingException(
                "Character data is expected to be set at the end of <{}>.".format(name)
            )

    def xml_element_end(self, name: str) -> None:

        if not self._current_page and name != 'sitemap:urlset':
            raise McSitemapsXMLParsingException("Page is expected to be set at the end of <{}>.".format(name))

        if name == 'sitemap:url':
            if self._current_page not in self._pages:
                self._pages.append(self._current_page)
            self._current_page = None

        else:

            if name == 'sitemap:loc':
                self.__require_last_char_data_to_be_set(name=name)
                self._current_page.url = self._last_char_data

            elif name == 'sitemap:lastmod':
                self.__require_last_char_data_to_be_set(name=name)
                self._current_page.last_modified = self._last_char_data

            elif name == 'sitemap:changefreq':
                self.__require_last_char_data_to_be_set(name=name)
                self._current_page.change_frequency = self._last_char_data

            elif name == 'sitemap:priority':
                self.__require_last_char_data_to_be_set(name=name)
                self._current_page.priority = self._last_char_data

            elif name == 'news:name':  # news/publication/name
                self.__require_last_char_data_to_be_set(name=name)
                self._current_page.news_publication_name = self._last_char_data

            elif name == 'news:language':  # news/publication/language
                self.__require_last_char_data_to_be_set(name=name)
                self._current_page.news_publication_language = self._last_char_data

            elif name == 'news:publication_date':
                self.__require_last_char_data_to_be_set(name=name)
                self._current_page.news_publish_date = self._last_char_data

            elif name == 'news:title':
                self.__require_last_char_data_to_be_set(name=name)
                self._current_page.news_title = self._last_char_data

            elif name == 'news:access':
                self.__require_last_char_data_to_be_set(name=name)
                self._current_page.news_access = self._last_char_data

            elif name == 'news:keywords':
                self.__require_last_char_data_to_be_set(name=name)
                self._current_page.news_keywords = self._last_char_data

            elif name == 'news:stock_tickers':
                self.__require_last_char_data_to_be_set(name=name)
                self._current_page.news_stock_tickers = self._last_char_data

        super().xml_element_end(name=name)

    def sitemap(self) -> AbstractSitemap:

        pages = []

        for page_row in self._pages:
            page = page_row.page()
            if page:
                pages.append(page)

        # noinspection PyArgumentList
        pages_sitemap = PagesXMLSitemap(url=self._url, pages=pages)

        return pages_sitemap
