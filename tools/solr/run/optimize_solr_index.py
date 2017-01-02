#!/usr/bin/env python3

import argparse

from mediawords.solr.run.constants import *
from mediawords.solr.run.solr import optimize_solr_index

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Optimize Solr index.",
                                     epilog="Index optimization triggered on one of the shards will trigger "
                                            "optimization on all of them.",
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument("-s", "--host", type=str, required=False, default="localhost",
                        help="Host (or one of the shards) running Solr to optimize.")
    parser.add_argument("-p", "--port", type=int, required=False, default=MC_SOLR_CLUSTER_STARTING_PORT,
                        help=("Solr port to connect to (use %d to trigger optimization on standalone instance)." %
                              MC_SOLR_STANDALONE_PORT))
    parser.add_argument("-c", "--collection", type=str, required=False, action="store", nargs="*", default=None,
                        help="Collection(s) to reindex. When omitted, all collections will be reindexed.")

    args = parser.parse_args()

    optimize_solr_index(host=args.host, port=args.port, collections=args.collection)
