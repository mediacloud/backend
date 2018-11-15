import abc
import datetime
from dataclasses import dataclass, field
from typing import List, Optional


@dataclass(frozen=True)
class SitemapStory(object):
    """Single sitemap-derived story."""

    # Spec defines that some of the properties below are "required" but in practice not every website provides the
    # required properties

    url: str
    """Story URL."""

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
class StoriesXMLSitemap(AbstractSitemap):
    """XML sitemap that contains links to stories."""

    stories: List[SitemapStory]
    """Stories found in the sitemap."""


@dataclass(frozen=True)
class AbstractIndexSitemap(AbstractSitemap):
    """Abstract sitemap with URLs to other sitemaps."""

    sub_sitemaps: List[AbstractSitemap]
    """Sub-sitemaps that are linked to from this sitemap."""


@dataclass(frozen=True)
class IndexXMLSitemap(AbstractIndexSitemap):
    """XML sitemap with URLs to other sitemaps."""
    pass


@dataclass(frozen=True)
class IndexRobotsTxtSitemap(AbstractIndexSitemap):
    """robots.txt sitemap with URLs to other sitemaps."""
    pass
