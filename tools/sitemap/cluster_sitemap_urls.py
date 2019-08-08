#!/usr/bin/env python3

import argparse
from collections import defaultdict

from sklearn.cluster import KMeans
from tqdm import tqdm

from mediawords.util.log import create_logger
from mediawords.util.sitemap.url_vectors import URLFeatureExtractor

log = create_logger(__name__)


def cluster_sitemap_urls(urls_path: str, cluster_count: int) -> None:
    """
    Cluster single website's sitemap URLs and print clusters from biggest to smallest.
    :param urls_path: Path to single website's sitemap URLs.
    :param cluster_count: K-means cluster count
    """
    urls = []

    log.info("Reading and vectorizing URLs...")
    with open(urls_path, mode='r', encoding='utf-8') as f:
        for line in tqdm(f):
            line = line.strip()
            url = URLFeatureExtractor(url=line)
            urls.append(url)

    assert len(urls), "Some URLs should have been read."

    log.info("Clustering...")
    kmeans = KMeans(n_clusters=cluster_count)
    labels = kmeans.fit_predict(urls)

    cluster_sizes = defaultdict(int)
    clusters = defaultdict(list)

    for label, url in zip(labels, urls):
        cluster_sizes[label] += 1
        clusters[label].append(url)

    # Print clusters from biggest to smallest
    for label, cluster_size in sorted(cluster_sizes.items(), key=lambda kv: kv[1], reverse=True):
        print(f"CLUSTER ({cluster_size} items):\n---\n\n")
        for url in clusters[label]:
            print(url)
        print("\n\n")


def main():
    parser = argparse.ArgumentParser(description="Cluster single website's sitemap URLs.",
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument("-u", "--urls_path", type=str, required=True,
                        help="Path to file with single website's sitemap URLs.")
    parser.add_argument("-c", "--cluster_count", type=str, required=False, default=2,
                        help="K-means cluster count.")

    args = parser.parse_args()

    cluster_sitemap_urls(urls_path=args.urls_path, cluster_count=args.cluster_count)


if __name__ == '__main__':
    main()
