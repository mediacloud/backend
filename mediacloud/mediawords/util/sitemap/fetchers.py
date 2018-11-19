import abc
import html
import re
import xml.parsers.expat
from dataclasses import field, dataclass
from typing import Optional, Dict

from furl import furl

from mediawords.util.log import create_logger
from mediawords.util.url import fix_common_url_mistakes, is_http_url, normalize_url, is_homepage_url
from mediawords.util.web.user_agent import UserAgent
from mediawords.util.sitemap.exceptions import McSitemapsException, McSitemapsXMLParsingException
from mediawords.util.sitemap.helpers import (
    sitemap_useragent,
    html_unescape_ignore_none,
    parse_sitemap_publication_date,
    get_url_retry_on_client_errors,
    ungzipped_response_content,
)
from mediawords.util.sitemap.objects import (
    AbstractSitemap,
    InvalidSitemap,
    IndexRobotsTxtSitemap,
    IndexXMLSitemap,
    SitemapStory,
    StoriesXMLSitemap,
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

        parser = xml.parsers.expat.ParserCreate()
        parser.StartElementHandler = self._xml_element_start
        parser.EndElementHandler = self._xml_element_end
        parser.CharacterDataHandler = self._xml_char_data

        log.info("Parsing sitemap from URL {}...".format(self._uri.url))
        try:
            is_final = True
            parser.Parse(sitemap_xml, is_final)
        except Exception as ex:
            # Some sitemap XML files might end abruptly because webservers might be timing out on returning huge XML
            # files so don't return InvalidSitemap() but try to get as much stories as possible
            log.error("Parsing sitemap from URL {} failed: {}".format(self._uri.url, ex))

        if not self._sitemap_parser:
            # noinspection PyArgumentList
            return InvalidSitemap(
                url=str(self._uri.url),
                reason="No parsers support sitemap from {}".format(self._uri.url),
            )

        return self._sitemap_parser.sitemap()

    def _xml_element_start(self, name: str, attrs: Dict[str, str]) -> None:

        # Strip namespace (if any)
        if ':' in name:
            name = name.split(':')[1]

        if self._sitemap_parser:
            self._sitemap_parser.xml_element_start(name=name, attrs=attrs)

        else:

            # Root element -- initialize concrete parser
            if name == 'urlset':
                self._sitemap_parser = StoriesXMLSitemapParser(url=str(self._uri.url))
            elif name == 'sitemapindex':
                self._sitemap_parser = IndexXMLSitemapParser(url=str(self._uri.url),
                                                             ua=self._ua,
                                                             recursion_level=self._recursion_level)
            else:
                raise McSitemapsXMLParsingException("Unsupported root element '{}'.".format(name))

    def _xml_element_end(self, name: str) -> None:

        # Strip namespace (if any)
        if ':' in name:
            name = name.split(':')[1]

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

        '_sub_sitemap_urls',
    ]

    def __init__(self, url: str, ua: UserAgent, recursion_level: int):
        super().__init__(url=url)

        self._ua = ua
        self._recursion_level = recursion_level
        self._sub_sitemap_urls = []

    def xml_element_end(self, name: str) -> None:

        if name == 'loc':
            sub_sitemap_url = html_unescape_ignore_none(self._last_char_data)
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


class StoriesXMLSitemapParser(AbstractXMLSitemapParser):
    """Stories XML sitemap parser."""

    @dataclass(unsafe_hash=True)
    class StoryRow(object):
        url: str = field(default=None, hash=True)
        title: str = None
        publish_date: str = None
        publication_name: str = None
        publication_language: str = None
        access: str = None
        genres: str = None
        keywords: str = None
        stock_tickers: str = None

        def story(self) -> Optional[SitemapStory]:
            """Return constructed sitemap story if one has been completed."""

            # Required
            url = html_unescape_ignore_none(self.url)
            if not url:
                log.warning("URL is unset")
                return None

            try:
                url = normalize_url(url)
            except Exception as ex:
                log.error("Unable to normalize URL {}: {}".format(url, ex))
                return None

            title = html_unescape_ignore_none(self.title)
            if not title:
                log.warning("Title is unset")
                return None

            publish_date = html_unescape_ignore_none(self.publish_date)
            if not publish_date:
                log.warning("Publish date is unset")
                return None
            publish_date = parse_sitemap_publication_date(date_string=publish_date)

            publication_name = html_unescape_ignore_none(self.publication_name)
            if not publication_name:
                log.warning("Publication name is unset")
                return None

            publication_language = html_unescape_ignore_none(self.publication_language)
            if not publication_language:
                log.warning("Publication language is unset")
                return None

            # Optional
            access = html_unescape_ignore_none(self.access)

            genres = html_unescape_ignore_none(self.genres)
            if genres:
                genres = [html.unescape(x.strip()) for x in genres.split(',')]
            else:
                genres = []

            keywords = html_unescape_ignore_none(self.keywords)
            if keywords:
                keywords = [html.unescape(x.strip()) for x in keywords.split(',')]
            else:
                keywords = []

            stock_tickers = html_unescape_ignore_none(self.stock_tickers)
            if stock_tickers:
                stock_tickers = [html.unescape(x.strip()) for x in stock_tickers.split(',')]
            else:
                stock_tickers = []

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
        '_current_story_row',
        '_story_rows',
    ]

    def __init__(self, url: str):
        super().__init__(url=url)

        self._current_story_row = None
        self._story_rows = []

    def xml_element_start(self, name: str, attrs: Dict[str, str]) -> None:

        super().xml_element_start(name=name, attrs=attrs)

        if name == 'url':
            if self._current_story_row:
                raise McSitemapsXMLParsingException("Story is expected to be unset by <url>.")
            self._current_story_row = StoriesXMLSitemapParser.StoryRow()

    def __require_last_char_data_to_be_set(self, name: str) -> None:
        if not self._last_char_data:
            raise McSitemapsXMLParsingException(
                "Character data is expected to be set at the end of <{}>.".format(name)
            )

    def xml_element_end(self, name: str) -> None:

        if not self._current_story_row and name != 'urlset':
            raise McSitemapsXMLParsingException("Story is expected to be set at the end of <{}>.".format(name))

        if name == 'url':
            if self._current_story_row not in self._story_rows:
                self._story_rows.append(self._current_story_row)
            self._current_story_row = None

        else:

            if name == 'loc':
                self.__require_last_char_data_to_be_set(name=name)
                self._current_story_row.url = self._last_char_data

            elif name == 'name':  # news/publication/name
                self.__require_last_char_data_to_be_set(name=name)
                self._current_story_row.publication_name = self._last_char_data

            elif name == 'language':  # news/publication/language
                self.__require_last_char_data_to_be_set(name=name)
                self._current_story_row.publication_language = self._last_char_data

            elif name == 'publication_date':
                self.__require_last_char_data_to_be_set(name=name)
                self._current_story_row.publish_date = self._last_char_data

            elif name == 'title':
                self.__require_last_char_data_to_be_set(name=name)
                self._current_story_row.title = self._last_char_data

            elif name == 'access':
                self.__require_last_char_data_to_be_set(name=name)
                self._current_story_row.access = self._last_char_data

            elif name == 'keywords':
                self.__require_last_char_data_to_be_set(name=name)
                self._current_story_row.keywords = self._last_char_data

            elif name == 'stock_tickers':
                self.__require_last_char_data_to_be_set(name=name)
                self._current_story_row.stock_tickers = self._last_char_data

        super().xml_element_end(name=name)

    def sitemap(self) -> AbstractSitemap:

        stories = []

        for story_row in self._story_rows:
            story = story_row.story()
            if story:
                stories.append(story)

        # noinspection PyArgumentList
        stories_sitemap = StoriesXMLSitemap(url=self._url, stories=stories)

        return stories_sitemap
