#!/usr/bin/env python

import argparse

from mc_solr.constants import *
from mc_solr.solr import run_solr_shard

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Install Solr and start a shard.",
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument("-n", "--shard_num", type=int, required=True,
                        help="Shard to start.")
    parser.add_argument("-c", "--shard_count", type=int, required=True,
                        help="Number of shards across the whole cluster.")
    parser.add_argument("-zh", "--zookeeper_host", type=str, required=False, default=MC_SOLR_CLUSTER_ZOOKEEPER_HOST,
                        help="ZooKeeper host to connect to.")
    parser.add_argument("-zp", "--zookeeper_port", type=int, required=False, default=MC_SOLR_CLUSTER_ZOOKEEPER_PORT,
                        help="ZooKeeper port to connect to.")
    parser.add_argument("-mx", "--jvm_heap_size", type=str, required=False, default=MC_SOLR_CLUSTER_JVM_HEAP_SIZE,
                        help="JVM heap size (-Xmx).")

    args = parser.parse_args()

    run_solr_shard(shard_num=args.shard_num,
                   shard_count=args.shard_count,
                   zookeeper_host=args.zookeeper_host,
                   zookeeper_port=args.zookeeper_port,
                   jvm_heap_size=args.jvm_heap_size)
