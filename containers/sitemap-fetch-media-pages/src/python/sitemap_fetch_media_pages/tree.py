from furl import furl

from mediawords.util.log import create_logger
from mediawords.util.url import is_homepage_url, is_http_url, normalize_url
from sitemap_fetch_media_pages.exceptions import McSitemapsException
from sitemap_fetch_media_pages.fetchers import SitemapFetcher
from sitemap_fetch_media_pages.objects import AbstractSitemap

log = create_logger(__name__)


def sitemap_tree_for_homepage(homepage_url: str) -> AbstractSitemap:
    """Using a homepage URL, fetch the tree of sitemaps and its stories."""

    if not is_http_url(homepage_url):
        raise McSitemapsException("URL {} is not a HTTP(s) URL.".format(homepage_url))

    try:
        url = normalize_url(homepage_url)
    except Exception as ex:
        raise McSitemapsException("Unable to normalize URL {}: {}".format(homepage_url, ex))

    try:
        uri = furl(url)
    except Exception as ex:
        raise McSitemapsException("Unable to parse URL {}: {}".format(url, ex))

    if not is_homepage_url(homepage_url):
        try:
            uri = uri.remove(path=True, query=True, query_params=True, fragment=True)
            log.warning("Assuming that the homepage of {} is {}".format(homepage_url, uri.url))
        except Exception as ex:
            raise McSitemapsException("Unable to determine homepage URL for URL {}: {}".format(homepage_url, ex))

    uri.path = '/robots.txt'
    robots_txt_url = str(uri.url)

    robots_txt_fetcher = SitemapFetcher(url=robots_txt_url, recursion_level=0)
    sitemap_tree = robots_txt_fetcher.sitemap()
    return sitemap_tree
