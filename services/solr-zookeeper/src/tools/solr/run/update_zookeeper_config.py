#!/usr/bin/env python3

import argparse

from mediawords.solr.run.constants import *
from mediawords.solr.run.solr import update_zookeeper_solr_configuration

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Update Solr's configuration on ZooKeeper.",
                                     epilog="This script does not reload Solr shards! " +
                                            "Run 'reload_solr_shards.py' afterwards.",
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument("-zh", "--zookeeper_host", type=str, required=False, default=MC_SOLR_CLUSTER_ZOOKEEPER_HOST,
                        help="ZooKeeper host to connect to.")
    parser.add_argument("-zp", "--zookeeper_port", type=int, required=False, default=MC_SOLR_CLUSTER_ZOOKEEPER_PORT,
                        help="ZooKeeper port to connect to.")

    args = parser.parse_args()

    update_zookeeper_solr_configuration(zookeeper_host=args.zookeeper_host, zookeeper_port=args.zookeeper_port)
