#!/usr/bin/env python3

import argparse

from mediawords.solr.run.solr import upgrade_lucene_standalone_index, upgrade_lucene_shards_indexes

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Upgrade Lucene index using IndexUpgrader utility.",
                                     epilog="Upgrade is needed when moving between major Solr versions (e.g. 4 to 5).",
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    shard_group = parser.add_mutually_exclusive_group(required=True)

    shard_group.add_argument("-s", "--standalone", action='store_true', help="Upgrade index of standalone instance.")
    shard_group.add_argument("-c", "--cluster", action='store_true', help="Upgrade indexes of Solr cluster shards.")

    args = parser.parse_args()

    if args.standalone:
        upgrade_lucene_standalone_index()
    else:
        upgrade_lucene_shards_indexes()
