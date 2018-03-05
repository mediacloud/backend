#!/usr/bin/env python3
"""Benchmark mediawords.util.html.html_strip()."""

import os
import statistics
import sys
import time

from mediawords.tm.fetch_link import content_matches_topic

def benchmark_html_strip() -> None:
    """Benchmark html_strip()."""
    if len(sys.argv) < 2:
        sys.exit("Usage: %s <directory of html files>" % sys.argv[0])

    directory = sys.argv[1]

    topic = {'pattern':
        """
(?: pizzagate | (?: (?: (?: clinton | trump ) .*? (?: pizza | pedo | epstein |
(?: (?: rape .*? (?: 13 | teen | doe | child | jane | lawsuit ) ) | (?: (?: 13 | teen | doe | child | jane | lawsuit ) .*?
rape ) ) ) ) | (?: (?: pizza | pedo | epstein | (?: (?: rape .*? (?: 13 | teen | doe | child | jane | lawsuit ) ) |
 (?: (?: 13 | teen | doe | child | jane | lawsuit ) .*? rape ) ) ) .*? (?: clinton | trump ) ) ) )
        """}
#     topic = {'pattern':
#                 """
# (?: pizzagate | (?: (?: (?: clinton | trump ) .*? (?: pizza | pedo | epstein |
# (?: (?: rape .*? (?: 13 | teen | doe | child | jane | lawsuit ) ) | (?: (?: 13 | teen | doe | child | jane | lawsuit ) .*?
# rape ) ) ) ) | (?: (?: pizza | pedo | epstein | (?: (?: rape .*? (?: 13 | teen | doe | child | jane | lawsuit ) ) |
#  (?: (?: 13 | teen | doe | child | jane | lawsuit ) .*? rape ) ) ) .*? (?: clinton | trump ) ) ) )
#                 """}

    times = []
    num_matches = 0
    files = os.listdir(directory)
    files = files

    for file in files:
        filename = os.fsdecode(file)
        if filename.endswith(".txt"):
            fh = open(os.path.join(directory, filename))
            content = fh.read()
            print(filename + ": " + str(len(content)))

            t1 = time.time()
            match = content_matches_topic(content, topic)
            t = time.time() - t1

            if match:
                num_matches += 1

            times.append(t)

            print("%s - %d" % (match, t))

    print("files: %d" % len(files))
    print("num_matches: %d" % num_matches)
    print("total: %f" % sum(times))
    print("max: %f" % max(times))
    print("median: %f" % statistics.median(times))
    print("high median: %f" % statistics.median_high(times))
    print("mean: %f" % statistics.mean(times))
    print("sd: %f" % statistics.stdev(times))


if __name__ == '__main__':
    benchmark_html_strip()
