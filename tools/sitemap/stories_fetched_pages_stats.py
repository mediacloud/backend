#!/usr/bin/env python3

import os
import sys
from typing import Set

from mediawords.util.sitemap.is_news_article import url_points_to_news_article


def _read_urls_into_set(file_path: str) -> Set[str]:
    result = set()
    if not os.path.isfile(file_path):
        return result
    with open(file_path, mode='r') as f:
        for url in f:
            url = url.strip()

            # Treat https:// and http:// as equal
            url = url.replace('https://', 'http://')

            # Normalize mobile and desktop version
            url = url.replace('//m.', '//www.')

            # elpais.com hack
            url = url.replace('//pro.', '//www.')

            # Treat www.example.com and example.com as equal
            url = url.replace('://www.', '://')

            result.add(url)

    return result


def print_stats_for_media(stories_dir: str, sitemaps_dir: str, media_id: str):
    assert os.path.isdir(stories_dir)
    assert os.path.isdir(sitemaps_dir)

    stories_path = os.path.join(stories_dir, media_id)
    sitemaps_path = os.path.join(sitemaps_dir, media_id)

    stories_urls = _read_urls_into_set(stories_path)
    sitemaps_urls = _read_urls_into_set(sitemaps_path)

    non_unique_url_count = len(stories_urls) + len(sitemaps_urls)
    unique_url_count = len(stories_urls | sitemaps_urls)

    stories_not_in_sitemaps = stories_urls.difference(sitemaps_urls)
    sitemaps_not_in_stories = sitemaps_urls.difference(stories_urls)

    news_article_sitemap_urls = set([url for url in sitemaps_urls if url_points_to_news_article(url)])
    news_article_sitemaps_not_in_stories = news_article_sitemap_urls.difference(stories_urls)

    print("\nNews article sitemap URLs:\n")
    for url in sorted(news_article_sitemap_urls):
        print(f"* {url}")

    print("\nNOT news article sitemap URLs:\n")
    for url in sorted(sitemaps_urls.difference(news_article_sitemap_urls)):
        print(f"* {url}")

    print()
    print(f"Stats for media ID {media_id}:")
    print("---")
    print()
    print(f"* Story URLs: {len(stories_urls)}")
    print(f"* Sitemap URLs: {len(sitemaps_urls)}")

    # print(f"* Total (non-unique) URLs: {non_unique_url_count}")
    print((
        f"* Total unique URLs: {unique_url_count} "
        f"({unique_url_count / (non_unique_url_count / 100):.1f}% of all story + sitemap URLs)"
    ))
    print()

    print((
        f"* Story URLs not found in sitemaps: {len(stories_not_in_sitemaps)} "
        f"({len(stories_not_in_sitemaps) / (len(stories_urls) / 100):.1f}% of all story URLs)")
    )
    print((
        f"* Sitemap URLs not found in stories: {len(sitemaps_not_in_stories)} "
        f"({len(sitemaps_not_in_stories) / (len(sitemaps_urls) / 100):.1f}% of all sitemap URLs)"
    ))

    print()
    print((
        f"* News article sitemap URLs: {len(news_article_sitemap_urls)} "
        f"({len(news_article_sitemap_urls) / (len(sitemaps_urls) / 100):.1f}% of all sitemap URLs)"
    ))

    print((
        f"* News article sitemap URLs not found in stories: {len(news_article_sitemaps_not_in_stories)} "
        f"({len(news_article_sitemaps_not_in_stories) / (len(sitemaps_urls) / 100):.1f}% of all sitemap URLs)"
    ))


def main():
    assert len(sys.argv) == 4, "Not enough arguments."

    stories_dir = sys.argv[1]
    sitemaps_dir = sys.argv[2]
    media_id = sys.argv[3]

    print_stats_for_media(stories_dir, sitemaps_dir, media_id)


if __name__ == '__main__':
    main()
