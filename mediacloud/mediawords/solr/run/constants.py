# Solr version to install and use
MC_SOLR_VERSION = "6.5.0"

# <luceneMatchVersion> value
MC_SOLR_LUCENEMATCHVERSION = "6.5.0"

# Solr home directory (solr.home; relative to Media Cloud root; must already exist)
MC_SOLR_HOME_DIR = "solr/"

# Base data directory under which both cluster (Solr and ZooKeeper) and non-cluster
# (only Solr) data will be stored (relative to Media Cloud root; must already exist)
MC_SOLR_BASE_DATA_DIR = "data/solr/"

# Seconds to wait for Solr to shutdown after SIGKILLing it; after the timeout, SIGTERM will be sent
MC_SOLR_SIGKILL_TIMEOUT = 60

# Solr starting port for shards, e.g.:
# * shard #1 will start on port MC_SOLR_CLUSTER_STARTING_PORT
# * shard #2 will start on port MC_SOLR_CLUSTER_STARTING_PORT+1
# * shard #3 will start on port MC_SOLR_CLUSTER_STARTING_PORT+2
# * ...
MC_SOLR_CLUSTER_STARTING_PORT = 7981

# Seconds to wait for a Solr shard to start
# (might want to make it bigger as a shard could be rebuilding indexes or whatever)
MC_SOLR_CLUSTER_CONNECT_RETRIES = 10 * 60

# Default ZooKeeper host to connect to
MC_SOLR_CLUSTER_ZOOKEEPER_HOST = "localhost"

# Default ZooKeeper port to connect to
MC_SOLR_CLUSTER_ZOOKEEPER_PORT = 9983

# Timeout in milliseconds at which solr shard disconnects from zookeeper
MC_SOLR_CLUSTER_ZOOKEEPER_TIMEOUT = 300000

# Seconds to wait for external ZooKeeper to start
MC_SOLR_CLUSTER_ZOOKEEPER_CONNECT_RETRIES = 2 * 60

# Default JVM heap size (-Xmx) for each shard
MC_SOLR_CLUSTER_JVM_HEAP_SIZE = "256m"

# Other JVM options to pass to each Solr shard in a cluster
MC_SOLR_CLUSTER_JVM_OPTS = [
]
