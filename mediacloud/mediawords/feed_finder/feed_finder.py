"""Class for finding the most likely url for an RSS/atom/other feed on a web page.

See https://github.com/dfm/feedfinder2 for other approaches to the same task.
"""
from urllib.parse import urljoin

from bs4 import BeautifulSoup
import requests

from mediawords.util.web.user_agent import UserAgent, McUserAgentException


def _is_feed_url(url):
    """Check if a url is a feed url with high confidence

    Wraps custom logic for high probability checks.

    Parameters
    ----------
    url : str
          Url that may or may not be a feed

    Returns
    -------
    boolean
        True if the string is a feed with high probability, or else False
    """
    endings = (
        '.rss',
        '.rdf',
        '.atom',
        '.xml',
    )
    url_lower = url.lower()
    return any(url_lower.endswith(ending) for ending in endings)


def _might_be_feed_url(url):
    """Check if a url might be a feed with moderate confidence

    A lower trust version of `_is_feed_url`
    Parameters
    ----------
    url : str
          Url that may or may not be a feed

    Returns
    -------
    boolean
        True if the string is a feed with reasonable probability, or else False
    """
    substrings = (
        'rss',
        'rdf',
        'atom',
        'xml',
        'feed'
    )
    url_lower = url.lower()
    return any(substring in url_lower for substring in substrings)


def filter_to_feeds(url_generator):
    """Helper to filter a url generator and remove non-feeds.

    This loads each url from the generator and inspects the underlying html.  It is quite slow,
    but accurate.

    Parameters
    ----------
    url_generator : iterator of strings
        Any iterator of strings that may be urls

    Yields
    ------
    str
        Any input string that resolves to a valid feed is yielded
    """
    for url in url_generator:
        if FeedFinder(url).is_feed():
            yield url


class FeedFinder(object):
    """A class to find possible RSS/Atom feeds on a web page.

    Usually easier to use `find_feed_url` or `generate_feed_urls`.
    The class defines a few methods for discovering links on a page, from
    first looking for standard feed links, then looking for *any* link, and then
    guessing at a few urls that are commonly used for feeds.  See
    `find_link_feeds`, `find_anchor_feeds`, and `guess_feed_links`, respectively.

    The class is used by either asking for a single feed, or all feeds.  All web
    fetching is deferred until needed, so it is typically much faster to only
    get a single feed, or to stop iterating over all feeds once a condition is
    satisfied.
    """
    def __init__(self, url, html=None):
        """Initialization

        Parameters
        ----------
        url : str
              A url that resolves to the webpage in question

        html : str (optional)
              To save a second web fetch, the raw html can be supplied
        """
        self.url = url
        self._html = html
        self._soup = None

    @property
    def html(self):
        """String of the html of the underlying site.

        If mediawords.util.web.user_agent.UserAgent.get throws an error, will
        return an empty string.
        """
        if self._html is None:
            ua = UserAgent()
            try:
                response = ua.get_follow_http_html_redirects(self.url)
            except McUserAgentException:
                self._html = ''
            else:
                if response.is_success():
                    self._html = response.decoded_content()
                else:
                    self._html = ''
        return self._html

    @property
    def soup(self):
        """BeautifulSoup representation of the data."""
        if self._soup is None:
            self._soup = BeautifulSoup(self.html, 'lxml')
        return self._soup

    def generate_feed_urls(self):
        """Generates an iterator of possible feeds, in rough order of likelihood."""
        if not self.html:
            return

        if self.is_feed():
            yield self.url
            return

        seen = set()
        for url_fn in (self.find_link_feeds, self.find_anchor_feeds, self.guess_feed_links):
            for url in filter_to_feeds(url_fn()):
                if url not in seen:
                    seen.add(url)
                    yield url

    def find_feed_url(self):
        """Fine the single most likely url as a feed for the page, or None."""
        try:
            return next(self.generate_feed_urls())
        except StopIteration:
            return None

    def is_feed(self):
        """Check if the site is a feed.

        Logic is to make sure there is no <html> tag, and there is some <rss> tag or similar.
        """
        invalid_tags = ('head',)
        if any(self.soup.find(tag) for tag in invalid_tags):
            return False

        valid_tags = ('rss', 'rdf', 'feed',)
        return any(self.soup.find(tag) for tag in valid_tags)

    def find_link_feeds(self):
        """Uses <link> tags to extract feeds

        for example:
            <link type="application/rss+xml" href="/might/be/relative.rss"></link>
        """
        valid_types = [
            "application/rss+xml",
            "text/xml",
            "application/atom+xml",
            "application/x.atom+xml",
            "application/x-atom+xml"
        ]

        link_tags = []
        for link in self.soup.find_all('link', type=valid_types):
            url = link.get('href')
            if url:
                link_tags.append(urljoin(base=self.url, url=url))
        return link_tags

    def find_anchor_feeds(self):
        """Uses <a></a> tags to extract feeds

        for example
            <a href="https://www.whatever.com/rss"></a>
        """
        seen = set()

        # This is outer loop so that most likely links
        # are produced first
        for url_filter in (_is_feed_url, _might_be_feed_url):
            for link in self.soup.find_all('a', href=True):
                url = link.get('href')
                if url not in seen and url_filter(url):
                    yield urljoin(base=self.url, url=url)
                    seen.add(url)

    def guess_feed_links(self):
        """Iterates common locations to find feeds.  These urls probably do not exist, but might

        Manual overrides should be added here.  For example, if foo.com has their rss feed at
        foo.com/here/for/reasons.rss, add 'here/for/reasons.rss' to the suffixes.
        """
        suffixes = (
            # Generic suffixes
            'index.xml', 'atom.xml', 'feeds', 'feeds/default', 'feed', 'feed/default',
            'feeds/posts/default/', '?feed=rss', '?feed=atom', '?feed=rss2', '?feed=rdf', 'rss',
            'atom', 'rdf', 'index.rss', 'index.rdf', 'index.atom',
            '?type=100',  # Typo3 RSS URL
            '?format=feed&type=rss',  # Joomla RSS URL
            'feeds/posts/default',  # Blogger.com RSS URL
            'data/rss',  # LiveJournal RSS URL
            'rss.xml',  # Posterous.com RSS feed
            'articles.rss', 'articles.atom',  # Patch.com RSS feeds
        )
        for suffix in suffixes:
            yield '/'.join([self.url, suffix])


def find_feed_url(url, html=None):
    """Find the single most likely feed url for a page.

    Parameters
    ----------
    url : str
          A url that resolves to the webpage in question

    html : str (optional)
          To save a second web fetch, the raw html can be supplied

    Returns
    -------
    str or None
       A url pointing to the most likely feed, if it exists.
    """
    return FeedFinder(url, html).find_feed_url()


def generate_feed_urls(url, html=None):
    """Find all feed urls for a page.

    Parameters
    ----------
    url : str
          A url that resolves to the webpage in question

    html : str (optional)
          To save a second web fetch, the raw html can be supplied

    Yields
    ------
    str or None
       A url pointing to a feed associated with the page
    """
    return FeedFinder(url, html).generate_feed_urls()
