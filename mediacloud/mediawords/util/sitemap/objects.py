import abc
import datetime
from dataclasses import dataclass, field
from decimal import Decimal
from enum import Enum, unique
from typing import List, Optional, Set

# As per the spec
SITEMAP_PAGE_DEFAULT_PRIORITY = Decimal('0.5')


@dataclass(frozen=True)
class SitemapNewsStory(object):
    """Single story derived from Google News XML sitemap."""

    # Spec defines that some of the properties below are "required" but in practice not every website provides the
    # required properties. So, we require only "title" and "publish_date" to be set.

    title: str
    """Story title."""

    publish_date: datetime.datetime
    """Story publication date."""

    publication_name: Optional[str] = None
    """Name of the news publication in which the article appears in."""

    publication_language: Optional[str] = None
    """Primary language of the news publication in which the article appears in.

    It should be an ISO 639 Language Code (either 2 or 3 letters)."""

    access: Optional[str] = None
    """Accessibility of the article."""

    genres: List[str] = field(default_factory=list, hash=False)
    """List of properties characterizing the content of the article, such as "PressRelease" or "UserGenerated"."""

    keywords: List[str] = field(default_factory=list, hash=False)
    """List of keywords describing the topic of the article."""

    stock_tickers: List[str] = field(default_factory=list, hash=False)
    """Comma-separated list of up to 5 stock tickers that are the main subject of the article.

    Each ticker must be prefixed by the name of its stock exchange, and must match its entry in Google Finance.
    For example, "NASDAQ:AMAT" (but not "NASD:AMAT"), or "BOM:500325" (but not "BOM:RIL")."""


@unique
class SitemapPageChangeFrequency(Enum):
    """Change frequency of a sitemap URL."""
    ALWAYS = 'always'
    HOURLY = 'hourly'
    DAILY = 'daily'
    WEEKLY = 'weekly'
    MONTHLY = 'monthly'
    YEARLY = 'yearly'
    NEVER = 'never'

    # Default change frequency for invalid input
    @classmethod
    def _missing_(cls, value):
        return SitemapPageChangeFrequency.ALWAYS


@dataclass(frozen=True)
class SitemapPage(object):
    """Single sitemap-derived page."""

    url: str
    """Page URL."""

    priority: Decimal = SITEMAP_PAGE_DEFAULT_PRIORITY
    """Priority of this URL relative to other URLs on your site."""

    last_modified: Optional[datetime.datetime] = None
    """Date of last modification of the URL."""

    change_frequency: Optional[SitemapPageChangeFrequency] = None
    """Change frequency of a sitemap URL."""

    news_story: Optional[SitemapNewsStory] = None
    """Google News story attached to the URL."""


@dataclass(frozen=True)
class AbstractSitemap(object, metaclass=abc.ABCMeta):
    """Abstract sitemap."""

    url: str
    """Sitemap URL."""

    @abc.abstractmethod
    def all_pages(self) -> Set[SitemapPage]:
        """Recursively return all stories from this sitemap and linked sitemaps."""
        raise NotImplementedError("Abstract method")


@dataclass(frozen=True)
class InvalidSitemap(AbstractSitemap):
    """Invalid sitemap, e.g. the one that can't be parsed."""

    reason: str
    """Reason why the sitemap is deemed invalid."""

    def all_pages(self) -> Set[SitemapPage]:
        return set()


@dataclass(frozen=True)
class AbstractPagesSitemap(AbstractSitemap, metaclass=abc.ABCMeta):
    """Abstract sitemap that contains URLs to pages."""

    pages: List[SitemapPage]
    """URLs to pages that were found in a sitemap."""

    def all_pages(self) -> Set[SitemapPage]:
        return set(self.pages)


@dataclass(frozen=True)
class PagesXMLSitemap(AbstractPagesSitemap):
    """XML sitemap that contains URLs to pages."""
    pass


@dataclass(frozen=True)
class PagesTextSitemap(AbstractPagesSitemap):
    """Plain text sitemap that contains URLs to pages."""
    pass


@dataclass(frozen=True)
class AbstractIndexSitemap(AbstractSitemap):
    """Abstract sitemap with URLs to other sitemaps."""

    sub_sitemaps: List[AbstractSitemap]
    """Sub-sitemaps that are linked to from this sitemap."""

    def all_pages(self) -> Set[SitemapPage]:
        pages = set()
        for sub_sitemap in self.sub_sitemaps:
            pages |= sub_sitemap.all_pages()
        return pages


@dataclass(frozen=True)
class IndexXMLSitemap(AbstractIndexSitemap):
    """XML sitemap with URLs to other sitemaps."""
    pass


@dataclass(frozen=True)
class IndexRobotsTxtSitemap(AbstractIndexSitemap):
    """robots.txt sitemap with URLs to other sitemaps."""
    pass
