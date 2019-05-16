#!/usr/bin/env python3

"""Convert a solr query to a regular expression."""

import sys

from webapp.solr.query.parse import parse_solr_query


def main():
    if len(sys.argv) < 2:
        return

    q = sys.argv[1]

    if len(q) == 0:
        return

    print(parse_solr_query(q).re())


main()
