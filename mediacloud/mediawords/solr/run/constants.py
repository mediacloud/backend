# Solr version to install and use
MC_SOLR_VERSION = "6.6.3"

# <luceneMatchVersion> value
MC_SOLR_LUCENEMATCHVERSION = "6.6.3"

# Solr home directory (solr.home; relative to Media Cloud root; must already exist)
MC_SOLR_HOME_DIR = "solr/"

# Base data directory under which both cluster (Solr and ZooKeeper) and non-cluster
# (only Solr) data will be stored (relative to Media Cloud root; must already exist)
MC_SOLR_BASE_DATA_DIR = "data/solr/"

# Seconds to wait for Solr to shutdown after SIGKILLing it; after the timeout, SIGTERM will be sent
MC_SOLR_SIGKILL_TIMEOUT = 60

# Solr port for running a standalone server
MC_SOLR_STANDALONE_PORT = 8983

# Seconds to wait for a standalone Solr instance to start
MC_SOLR_STANDALONE_CONNECT_RETRIES = 2 * 60

# Default JVM heap size (-Xmx) for a standalone instance
MC_SOLR_STANDALONE_JVM_HEAP_SIZE = "256m"

# Other JVM options to pass to Solr when running a standalone instance
MC_SOLR_STANDALONE_JVM_OPTS = [
]

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

# ---

# ZooKeeper version to install and use
MC_ZOOKEEPER_VERSION = "3.4.10"

# Default ZooKeeper host to bind to, e.g. "localhost"
MC_ZOOKEEPER_LISTEN = "0.0.0.0"

# Default ZooKeeper port to listen to
MC_ZOOKEEPER_PORT = MC_SOLR_CLUSTER_ZOOKEEPER_PORT

# Seconds to wait for ZooKeeper to start
MC_ZOOKEEPER_CONNECT_RETRIES = 2 * 60

# Seconds to wait for ZooKeeper to shutdown after SIGKILLing it; after the timeout, SIGTERM will be sent
MC_ZOOKEEPER_SIGKILL_TIMEOUT = 60

# ---

# Timeout for installations (in seconds)
MC_INSTALL_TIMEOUT = 2 * 60

# Where to extract software distributions (relative to Media Cloud root; must already exist)
MC_DIST_DIR = "data/solr/dist/"

# File placed in distribution directory which signifies that distribution is being installed right now
MC_PACKAGE_INSTALLING_FILE = "mc-installing.txt"

# File placed in distribution directory which signifies that distribution was installed and started successfully
MC_PACKAGE_INSTALLED_FILE = "mc-installed.txt"
