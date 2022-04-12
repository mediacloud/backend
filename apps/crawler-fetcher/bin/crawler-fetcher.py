#!/usr/bin/env python3

import os

from crawler_fetcher.engine import run_fetcher

if __name__ == '__main__':
    # not yet tested: queue parsing to feed_parse_worker
    run_fetcher(queue=os.environ.get('MC_FEED_PARSE_QUEUE'))
