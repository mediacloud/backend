from mediawords.util.sitemap.fetchers import IndexRobotsTxtSitemapFetcher
from mediawords.util.sitemap.objects import AbstractSitemap


def sitemap_tree_for_homepage(homepage_url: str) -> AbstractSitemap:
    """Using a homepage URL, fetch the tree of sitemaps and its stories."""
    robots_txt_fetcher = IndexRobotsTxtSitemapFetcher(homepage_url=homepage_url)
    sitemap_tree = robots_txt_fetcher.sitemap()
    return sitemap_tree
