#!/usr/bin/env python
"""Convert a solr query to a regular expression."""

import sys

import mediawords.solr.query

def main():
    if len(sys.argv) < 2:
        return

    q = sys.argv[1]

    if len(q) == 0:
        return

    print(mediawords.solr.query.parse(q).re())

main()
