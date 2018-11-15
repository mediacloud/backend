#!/usr/bin/env python3

"""Sitemap feed evaluation."""

from mediawords.util.log import create_logger
from mediawords.util.sitemap.tree import sitemap_tree_for_homepage

log = create_logger(__name__)

if __name__ == "__main__":
    url = 'https://www.15min.lt///'
    sitemap_tree = sitemap_tree_for_homepage(homepage_url=url)
    print(sitemap_tree)
