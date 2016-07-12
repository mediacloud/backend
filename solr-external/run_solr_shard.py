#!/usr/bin/env python

import argparse

from mc_solr.solr import run_solr_shard

if __name__ == "__main__":
    run_solr_shard(shard_num=1, shard_count=2)
