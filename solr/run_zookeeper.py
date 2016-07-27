#!/usr/bin/env python

import argparse

from mc_solr.constants import *
from mc_solr.zookeeper import run_zookeeper

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Install and run ZooKeeper instance.",
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument("-l", "--listen", type=str, required=False, default=MC_ZOOKEEPER_LISTEN,
                        help="Address to bind to.")
    parser.add_argument("-p", "--port", type=int, required=False, default=MC_ZOOKEEPER_PORT,
                        help="Port to listen to.")

    args = parser.parse_args()

    run_zookeeper(listen=args.listen, port=args.port)
