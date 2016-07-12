# Solr version to install and use
MC_SOLR_VERSION = "4.6.0"

# <luceneMatchVersion> value
MC_SOLR_LUCENEMATCHVERSION = "LUCENE_46"

# Solr home directory (solr.home; relative to solr/; must already exist)
MC_SOLR_HOME_DIR = "mediacloud/"

# Solr data directory (relative to solr/; must already exist)
MC_SOLR_DATA_DIR = "../data/solr/"

# Solr starting port for shards
MC_SOLR_CLUSTER_STARTING_PORT = 7980

# Default ZooKeeper host to connect to
MC_SOLR_CLUSTER_ZOOKEEPER_HOST = "localhost"

# Default ZooKeeper port to connect to
MC_SOLR_CLUSTER_ZOOKEEPER_PORT = 9983

# Other JVM options to pass to each Solr shard in a cluster
MC_SOLR_CLUSTER_JVM_OPTS = [
    "-Xmx256m",
    # "-XX:+PrintGC",
    # "-XX:+UsePerfData",
    # "-XX:+UseG1GC",
    # "-XX:+PerfDisableSharedMem",
    # "-XX:+ParallelRefProcEnabled",
    # "-XX:G1HeapRegionSize=12m",
    # "-XX:MaxGCPauseMillis=250",
    # "-XX:InitiatingHeapOccupancyPercent=75",
    # "-XX:+UseLargePages",
    # "-XX:+AggressiveOpts",
]

# Solr port for running a standalone server
MC_SOLR_STANDALONE_PORT = 8983

# Other JVM options to pass to Solr when running a standalone instance
MC_SOLR_STANDALONE_JVM_OPTS = [
    "-Xmx256m",
]

# ---

# ZooKeeper version to install and use
MC_ZOOKEEPER_VERSION = "3.4.8"

# Default ZooKeeper host to bind to, e.g. "localhost"
MC_ZOOKEEPER_LISTEN = "0.0.0.0"

# Default ZooKeeper port to listen to
MC_ZOOKEEPER_PORT = MC_SOLR_CLUSTER_ZOOKEEPER_PORT

# ZooKeeper data directory (relative to solr/; must already exist)
MC_ZOOKEEPER_DATA_DIR = "../data/solr-zookeeper/"

# ---

# Timeout for installations (in seconds)
MC_INSTALL_TIMEOUT = 120

# Where to extract software distributions (relative to solr/; must already exist)
MC_DIST_DIR = "dist"

# File placed in distribution directory which signifies that distribution is being installed right now
MC_PACKAGE_INSTALLING_FILE = "mc-installing.txt"

# File placed in distribution directory which signifies that distribution was installed and started successfully
MC_PACKAGE_INSTALLED_FILE = "mc-installed.txt"
