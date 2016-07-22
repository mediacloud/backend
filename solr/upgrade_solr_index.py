#!/usr/bin/env python

import argparse

from mc_solr.constants import *
from mc_solr.solr import update_zookeeper_solr_configuration, upgrade_solr_standalone_index, upgrade_solr_shards_indexes

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Upgrade Solr (Lucene) index using IndexUpgrader utility.",
                                     epilog="Upgrade is needed when moving between major Solr versions (e.g. 4 to 5).",
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    shard_group = parser.add_mutually_exclusive_group(required=True)

    shard_group.add_argument("-s", "--standalone", action='store_true', help="Upgrade index of standalone instance.")
    shard_group.add_argument("-c", "--cluster", action='store_true', help="Upgrade indexes of Solr cluster shards.")

    args = parser.parse_args()

    if args.standalone:
        upgrade_solr_standalone_index()
    else:
        upgrade_solr_shards_indexes()
