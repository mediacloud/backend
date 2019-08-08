#!/usr/bin/env python3

import argparse
from typing import Iterator

from tqdm import tqdm

from mediawords.util.sitemap.is_news_article import url_points_to_news_article
from mediawords.util.sitemap.url_vectors import URLFeatureExtractor


def vectorize_sitemap_urls(urls_path: str) -> Iterator:
    """
    Vectorize every sitemap URL and yield a string with tab-separated URL, its vectors, and integer denoting whether it
    looks like a news article URL.

    Sample yielded line:

        "https://example.com/article-01/    0   0   1   ... 1"
        (URL)                               (vectors)       (1 if URL points to a news article, 0 otherwise)

    :param urls_path: Path to file with sitemap URLs.
    :return: Iterator to lines to print to STDOUT.
    """
    with open(urls_path, mode='r', encoding='utf-8') as f:
        for line in tqdm(f):
            line = line.strip()
            url = URLFeatureExtractor(url=line)

            output = ""

            output += url.url()
            output += "\t"

            for url_vector in url.vectors():
                if isinstance(url_vector, bool):
                    output += '1' if url_vector else '0'
                else:
                    output += str(url_vector)
                output += "\t"

            output += "1" if url_points_to_news_article(url.url()) else "0"

            yield output


def main():
    parser = argparse.ArgumentParser(description="Vectorize sitemap URLs.",
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument("-u", "--urls_path", type=str, required=True, help="Path to file with sitemap URLs.")

    args = parser.parse_args()

    for line in vectorize_sitemap_urls(urls_path=args.urls_path):
        print(line)


if __name__ == '__main__':
    main()
