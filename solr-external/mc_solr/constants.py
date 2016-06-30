# Solr version to install and use
MC_SOLR_VERSION = "4.6.0"

# Solr home directory (solr.home; relative to solr/; must already exist)
MC_SOLR_HOME_DIR = "mediacloud/"

# ---

# ZooKeeper version to install and use
MC_ZOOKEEPER_VERSION = "3.4.8"

# Default ZooKeeper host to bind to, e.g. "localhost"
MC_ZOOKEEPER_LISTEN = "0.0.0.0"

# Default ZooKeeper port
MC_ZOOKEEPER_PORT = 9983

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
