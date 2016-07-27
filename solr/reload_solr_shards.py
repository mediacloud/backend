#!/usr/bin/env python

import argparse

from mc_solr.solr import reload_all_solr_shards

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Reload Solr shards with updated configuration on ZooKeeper.",
                                     epilog="This script does not update configuration on ZooKeeper itself! " +
                                            "Run 'update_zookeeper_config.py' before.",
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument("-c", "--shard_count", type=int, required=True, help="Number of shards to expect on each host.")
    parser.add_argument("-s", "--host", type=str, required=False, action="store", nargs="*", default=["localhost"],
                        help="Host(s) running Solr to reload.")

    args = parser.parse_args()

    for host in args.host:
        reload_all_solr_shards(shard_count=args.shard_count, host=host)
