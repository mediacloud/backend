#!/usr/bin/env python3
"""Benchmark mediawords.util.html.html_strip()."""

import os
import sys
import time

from mediawords.util.html import html_strip


def benchmark_html_strip() -> None:
    """Benchmark html_strip()."""
    if len(sys.argv) < 2:
        sys.exit("Usage: %s <directory of html files>" % sys.argv[0])

    directory = sys.argv[1]

    benchmark_total = 0.0
    files = os.listdir(directory)
    for file in files:
        filename = os.fsdecode(file)
        if filename.endswith(".txt"):
            fh = open(os.path.join(directory, filename))
            content = fh.read()
            print(filename + ": " + str(len(content)))

            t1 = time.time()
            text = html_strip(content)
            benchmark_total += (time.time() - t1)

            print(text[0:64] + "...")

    print("files: " + str(len(files)))
    print("total time: " + str(benchmark_total))


if __name__ == '__main__':
    benchmark_html_strip()
