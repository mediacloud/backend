#!/usr/bin/env python3

import os
import sys

from mediawords.tm.guess_date import guess_date


def benchmark_date_guessing():
    """Benchmark Python date guessing code."""
    if len(sys.argv) < 2:
        sys.exit("Usage: %s <directory of html files>" % sys.argv[0])

    directory = sys.argv[1]

    for file in os.listdir(directory):
        filename = os.fsdecode(file)
        if filename.endswith(".txt"):
            fh = open(os.path.join(directory, filename))
            content = fh.read()
            print(filename + ": " + str(len(content)))
            date_guess = guess_date(url='http://dont.know.the.date/some/path.html',
                                    html=content)
            print(date_guess.date)
            print(date_guess.guess_method)


if __name__ == '__main__':
    benchmark_date_guessing()
