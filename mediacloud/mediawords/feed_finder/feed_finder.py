from urllib.parse import urljoin

from bs4 import BeautifulSoup

from mediawords.util.web.user_agent import UserAgent, McUserAgentException


def _is_feed_url(url):
    endings = (
        '.rss',
        '.rdf',
        '.atom',
        '.xml',
    )
    url_lower = url.lower()
    return any(url_lower.endswith(ending) for ending in endings)


def _might_be_feed_url(url):
    substrings = (
        'rss',
        'rdf',
        'atom',
        'xml',
        'feed'
    )
    url_lower = url.lower()
    return any(substring in url_lower for substring in substrings)


class FeedFinder(object):

    def __init__(self, url, html=None):
        self.url = url
        self._html = html
        self._soup = None

    @property
    def html(self):
        """String of the html of the underlying site."""
        if self._html is None:
            ua = UserAgent()
            try:
                response = ua.get_follow_http_html_redirects(self.url)
            except McUserAgentException:
                self._html = ''
            else:
                self._html = response.as_string()
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

        for url_fn in (self.find_link_feeds, self.find_anchor_feeds, self.guess_feed_links):
            yield from filter_to_feeds(url_fn())

    def find_feed_url(self):
        """Fine the single most likely url as a feed for the page, or None."""
        try:
            return next(self.generate_feed_urls())
        except StopIteration:
            return None

    def is_feed(self):
        """Check if the site is a feed.

        Logic is to make sure there is no <html></html> tag, and there is some
        <rss></rss> tag or similar.
        """
        lower_html = self.html.lower()

        invalid_tags = ('html',)
        if any('<{}'.format(tag) in lower_html for tag in invalid_tags):
            return False

        valid_tags = ('rss', 'rdf', 'feed',)
        return any('<{}'.format(tag) for tag in valid_tags)

    def find_link_feeds(self):
        """Uses <link></link> tags to extract feeds

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
            yield urljoin(base=self.url, url=suffix)


def find_feed_url(url, html=None):
    return FeedFinder(url, html).find_feed_url()


def generate_feed_urls(url, html=None):
    return FeedFinder(url, html).generate_feed_urls()


def filter_to_feeds(url_generator):
    """Helper to filter a url generator and remove non-feeds."""
    for url in url_generator:
        if FeedFinder(url).is_feed():
            yield url
