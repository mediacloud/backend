import urllib2

from mc_solr.constants import *
from mc_solr.distpath import distribution_path
from mc_solr.utils import *

logger = create_logger(__name__)


def __solr_path(dist_directory=MC_DIST_DIR, solr_version=MC_SOLR_VERSION):
    """Return path to where Solr distribution should be located."""
    dist_path = distribution_path(dist_directory=dist_directory)
    solr_directory = "solr-%s" % solr_version
    solr_path = os.path.join(dist_path, solr_directory)
    return solr_path


def __solr_installing_file_path(dist_directory=MC_DIST_DIR, solr_version=MC_SOLR_VERSION):
    """Return path to file which denotes that Solr is being installed (and thus serves as a lock file)."""
    solr_path = __solr_path(dist_directory=dist_directory, solr_version=solr_version)
    return os.path.join(solr_path, MC_PACKAGE_INSTALLING_FILE)


def __solr_installed_file_path(dist_directory=MC_DIST_DIR, solr_version=MC_SOLR_VERSION):
    """Return path to file which denotes that Solr has been installed."""
    solr_path = __solr_path(dist_directory=dist_directory, solr_version=solr_version)
    return os.path.join(solr_path, MC_PACKAGE_INSTALLED_FILE)


def __solr_dist_url(solr_version=MC_SOLR_VERSION):
    """Return URL to download Solr from."""
    solr_dist_url = "https://archive.apache.org/dist/lucene/solr/%(solr_version)s/solr-%(solr_version)s.tgz" % {
        "solr_version": solr_version,
    }
    return solr_dist_url


def __solr_is_installed(dist_directory=MC_DIST_DIR, solr_version=MC_SOLR_VERSION):
    """Return True if Solr is installed in distribution path."""
    solr_path = __solr_path(dist_directory=dist_directory, solr_version=solr_version)
    installed_file_path = __solr_installed_file_path(dist_directory=dist_directory, solr_version=solr_version)

    if os.path.isfile(installed_file_path):
        if os.path.isfile(os.path.join(solr_path, "README.txt")):
            return True
        else:
            logger.warn(
                "Solr distribution was not found at path '%s' even though it was supposed to be there." % solr_path)
            os.unlink(installed_file_path)

    return False


def __install_solr(dist_directory=MC_DIST_DIR, solr_version=MC_SOLR_VERSION):
    """Install Solr to distribution directory; lock directory before installing and unlock afterwards."""
    if __solr_is_installed(dist_directory=dist_directory, solr_version=solr_version):
        raise Exception("Solr %s is already installed in distribution directory '%s'." % (
            solr_version, dist_directory
        ))

    solr_path = __solr_path(dist_directory=dist_directory, solr_version=solr_version)

    logger.info("Creating Solr directory...")
    mkdir_p(solr_path)

    installing_file_path = __solr_installing_file_path(dist_directory=dist_directory, solr_version=solr_version)

    logger.info("Locking Solr directory for installation...")
    lock_file(installing_file_path, timeout=MC_INSTALL_TIMEOUT)

    # Waited for concurrent installation to finish?
    if __solr_is_installed(dist_directory=dist_directory, solr_version=solr_version):
        logger.info("While waiting for Solr directory to unlock, Solr got installed to said directory.")
        return

    solr_dist_url = __solr_dist_url(solr_version=solr_version)

    logger.info("Downloading Solr %s from %s..." % (solr_version, solr_dist_url))
    solr_tarball_dest_path = download_file_to_temp_path(solr_dist_url)

    logger.info("Extracting %s to %s..." % (solr_tarball_dest_path, solr_path))
    extract_tarball_to_directory(archive_file=solr_tarball_dest_path,
                                 dest_directory=solr_path,
                                 strip_root=True)

    # Solr 4 needs its .war extracted first before ZkCLI is usable
    solr_war_path = os.path.join(solr_path, "example", "webapps", "solr.war")
    if os.path.isfile(solr_war_path):
        solr_war_dest_dir = os.path.join(solr_path, "example", "solr-webapp", "webapp")
        logger.info("Extracting solr.war at '%s' to '%s'..." % (solr_war_path, solr_war_dest_dir))
        mkdir_p(solr_war_dest_dir)
        extract_tarball_to_directory(archive_file=solr_war_path, dest_directory=solr_war_dest_dir)

    logger.info("Creating 'installed' file...")
    installed_file_path = __solr_installed_file_path(dist_directory=dist_directory, solr_version=solr_version)
    lock_file(installed_file_path)

    logger.info("Removing lock file...")
    unlock_file(installing_file_path)

    if not __solr_is_installed(dist_directory=dist_directory, solr_version=solr_version):
        raise Exception("I've done everything but Solr is still not installed.")


def __solr_home_path(solr_home_dir=MC_SOLR_HOME_DIR):
    """Return path to Solr home (with collection subdirectories)."""
    script_path = os.path.dirname(os.path.abspath(__file__))
    solr_home_path = os.path.join(script_path, "..", solr_home_dir)
    if not os.path.isdir(solr_home_path):
        raise Exception("Solr home directory '%s' at path '%s' does not exist." % (
            solr_home_dir,
            solr_home_path
        ))
    return solr_home_path


def __solr_collections_path(solr_home_dir=MC_SOLR_HOME_DIR):
    solr_home_path = __solr_home_path(solr_home_dir=solr_home_dir)
    collections_path = os.path.join(solr_home_path, "collections/")
    if not os.path.isdir(collections_path):
        raise Exception("Collections directory does not exist at path '%s'" % collections_path)
    logger.debug("Collections path: %s" % collections_path)
    return collections_path


def __solr_collections(solr_home_dir=MC_SOLR_HOME_DIR):
    """Return dictionary with names and absolute paths to Solr collections."""
    collections = {}
    collections_path = __solr_collections_path(solr_home_dir)
    collection_names = os.listdir(collections_path)
    logger.debug("Files in collections directory: %s" % collection_names)
    for name in collection_names:
        if not (name.startswith("_") or name.startswith(".")):
            full_path = os.path.join(collections_path, name)
            if os.path.isdir(full_path):

                collection_conf_path = os.path.join(full_path, "conf")
                if not os.path.isdir(collection_conf_path):
                    raise Exception("Collection configuration path for collection '%s' does not exist." % name)

                collections[name] = full_path

    return collections


def __shard_name(shard_num):
    """Return shard name."""
    if shard_num < 1:
        raise Exception("Shard number must be 1 or greater.")
    return "mediacloud-shard-%d" % shard_num


def __shard_port(shard_num, starting_port=MC_SOLR_CLUSTER_STARTING_PORT):
    """Return port on which a shard should listen to."""
    if shard_num < 1:
        raise Exception("Shard number must be 1 or greater.")
    return starting_port + shard_num - 1


def __shard_data_dir(shard_num, data_dir=MC_SOLR_DATA_DIR):
    """Return data directory for a shard."""
    if shard_num < 1:
        raise Exception("Shard number must be 1 or greater.")
    if not os.path.isdir(data_dir):
        raise Exception("Solr data directory '%s' does not exist." % data_dir)
    shard_name = __shard_name(shard_num=shard_num)
    return os.path.join(data_dir, shard_name)


def __run_solr_zkcli(args,
                     zookeeper_host=MC_SOLR_CLUSTER_ZOOKEEPER_HOST,
                     zookeeper_port=MC_SOLR_CLUSTER_ZOOKEEPER_PORT,
                     dist_directory=MC_DIST_DIR,
                     solr_version=MC_SOLR_VERSION):
    """Run Solr's zkcli.sh helper script."""
    solr_path = __solr_path(dist_directory=dist_directory, solr_version=solr_version)

    # Solr 4
    log4j_properties_path = os.path.join(solr_path, "example", "cloud-scripts", "log4j.properties")
    if not os.path.isfile(log4j_properties_path):
        log4j_properties_path = os.path.join(solr_path, "server", "scripts", "cloud-scripts", "log4j.properties")
        if not os.path.isfile(log4j_properties_path):
            raise Exception("Unable to find log4j.properties file for zkcli.sh script")

    if not tcp_port_is_open(hostname=zookeeper_host, port=zookeeper_port):
        raise Exception("ZooKeeper is not running at %s:%d." % (zookeeper_host, zookeeper_port))

    zkhost = "%s:%d" % (zookeeper_host, zookeeper_port)

    java_classpath_dirs = [
        # Solr 4
        os.path.join(solr_path, "dist", "*"),
        os.path.join(solr_path, "example", "solr-webapp", "webapp", "WEB-INF", "lib", "*"),
        os.path.join(solr_path, "example", "lib", "ext", "*"),
    ]
    subprocess.check_call(["java",
                           "-classpath", ":".join(java_classpath_dirs),
                           "-Dlog4j.configuration=file://" + os.path.abspath(log4j_properties_path),
                           "org.apache.solr.cloud.ZkCLI",
                           "-zkhost", zkhost] + args)


def update_zookeeper_solr_configuration(zookeeper_host=MC_SOLR_CLUSTER_ZOOKEEPER_HOST,
                                        zookeeper_port=MC_SOLR_CLUSTER_ZOOKEEPER_PORT,
                                        dist_directory=MC_DIST_DIR,
                                        solr_version=MC_SOLR_VERSION):
    """Update Solr's configuration on ZooKeeper."""
    if not __solr_is_installed():
        logger.info("Solr is not installed, installing...")
        __install_solr()

    if not tcp_port_is_open(hostname=zookeeper_host, port=zookeeper_port):
        raise Exception("ZooKeeper is not running at %s:%d." % (zookeeper_host, zookeeper_port))

    collections = __solr_collections()
    logger.debug("Solr collections: %s" % collections)

    logger.info("Uploading Solr collection configurations to ZooKeeper...")
    for collection_name, collection_path in sorted(collections.items()):
        collection_conf_path = os.path.join(collection_path, "conf")

        logger.info("Uploading collection's '%s' configuration at '%s'..." % (collection_name, collection_conf_path))
        __run_solr_zkcli(args=["-cmd", "upconfig",
                               "-confdir", collection_conf_path,
                               "-confname", collection_name],
                         zookeeper_host=zookeeper_host,
                         zookeeper_port=zookeeper_port,
                         dist_directory=dist_directory,
                         solr_version=solr_version)

        logger.info("Linking collection's '%s' configuration..." % collection_name)
        __run_solr_zkcli(args=["-cmd", "linkconfig",
                               "-collection", collection_name,
                               "-confname", collection_name],
                         zookeeper_host=zookeeper_host,
                         zookeeper_port=zookeeper_port,
                         dist_directory=dist_directory,
                         solr_version=solr_version)

    logger.info("Uploaded Solr collection configurations to ZooKeeper.")


def run_solr(port,
             instance_data_dir,
             start_jar_args=None,
             jvm_opts=None,
             jvm_heap_size_limit=MC_SOLR_JVM_HEAP_SIZE_LIMIT,
             dist_directory=MC_DIST_DIR,
             solr_version=MC_SOLR_VERSION):
    """Run Solr instance."""
    if jvm_opts is None:
        jvm_opts = MC_SOLR_STANDALONE_JVM_OPTS

    if start_jar_args is None:
        start_jar_args = []

    if not __solr_is_installed():
        logger.info("Solr is not installed, installing...")
        __install_solr()

    solr_home_dir = __solr_home_path(solr_home_dir=MC_SOLR_HOME_DIR)
    if not os.path.isdir(solr_home_dir):
        raise Exception("Solr home directory '%s' does not exist." % solr_home_dir)

    solr_path = __solr_path(dist_directory=dist_directory, solr_version=solr_version)

    if not os.path.isdir(instance_data_dir):
        logger.info("Creating data directory at %s..." % instance_data_dir)
        mkdir_p(instance_data_dir)

    logger.info("Updating collections at %s..." % instance_data_dir)
    collections = __solr_collections(solr_home_dir=solr_home_dir)
    for collection_name, collection_path in sorted(collections.items()):
        logger.info("Updating collection '%s'..." % collection_name)

        conf_symlink_src_dir = os.path.join(collection_path, "conf")
        if not os.path.isdir(conf_symlink_src_dir):
            raise Exception("Configuration for collection '%s' at %s does not exist" % (
                collection_name, conf_symlink_src_dir
            ))

        collection_dst_dir = os.path.join(instance_data_dir, collection_name)
        mkdir_p(collection_dst_dir)

        conf_symlink_dst_dir = os.path.join(collection_dst_dir, "conf")
        if os.path.exists(conf_symlink_dst_dir):
            if not os.path.islink(conf_symlink_dst_dir):
                raise Exception("Collection configuration '%s' exists but is not a symlink." % conf_symlink_dst_dir)
        else:
            logger.info("Symlinking '%s' to '%s'..." % (conf_symlink_src_dir, conf_symlink_dst_dir))
            os.symlink(conf_symlink_src_dir, conf_symlink_dst_dir)

        logger.info("Updating core.properties for collection '%s'..." % collection_name)
        core_properties_path = os.path.join(collection_dst_dir, "core.properties")
        with open(core_properties_path, 'w') as core_properties_file:
            core_properties_file.write("""
#
# This file is autogenerated. Don't bother editing it!
#

name=%(collection_name)s
instanceDir=%(instance_dir)s
""" % {
                "collection_name": collection_name,
                "instance_dir": collection_dst_dir,
            })

    logger.info("Symlinking shard configuration...")
    config_items_to_symlink = [
        "contexts",
        "etc",
        "resources",
        "solr.xml",
    ]
    for config_item in config_items_to_symlink:
        config_item_src_path = os.path.join(solr_home_dir, config_item)
        if not os.path.exists(config_item_src_path):
            raise Exception("Expected configuration item '%s' does not exist" % config_item_src_path)

        # Recreate symlink just in case
        config_item_dst_path = os.path.join(instance_data_dir, config_item)
        if os.path.exists(config_item_dst_path):
            if not os.path.islink(config_item_dst_path):
                raise Exception("Configuration item '%s' exists but is not a symlink." % config_item_dst_path)
            os.unlink(config_item_dst_path)

        logger.info("Symlinking '%s' to '%s'..." % (config_item_src_path, config_item_dst_path))
        os.symlink(config_item_src_path, config_item_dst_path)

    logger.info("Symlinking libraries and JARs...")
    library_items_to_symlink = [
        "lib",
        "solr-webapp",
        "start.jar",
        "webapps",
    ]
    for library_item in library_items_to_symlink:
        library_item_src_path = os.path.join(solr_path, "example", library_item)
        if not os.path.exists(library_item_src_path):
            raise Exception("Expected library item '%s' does not exist" % library_item_src_path)

        # Recreate symlink just in case
        library_item_dst_path = os.path.join(instance_data_dir, library_item)
        if os.path.exists(library_item_dst_path):
            if not os.path.islink(library_item_dst_path):
                raise Exception("Library item '%s' exists but is not a symlink." % library_item_dst_path)
            os.unlink(library_item_dst_path)

        logger.info("Symlinking '%s' to '%s'..." % (library_item_src_path, library_item_dst_path))
        os.symlink(library_item_src_path, library_item_dst_path)

    jetty_home_dir = os.path.join(solr_path, "example")
    if not os.path.isdir(jetty_home_dir):
        raise Exception("Jetty home directory '%s' does not exist." % jetty_home_dir)

    log4j_properties_path = os.path.join(solr_home_dir, "resources", "log4j.properties")
    if not os.path.isfile(log4j_properties_path):
        raise Exception("log4j.properties at '%s' was not found.")

    start_jar_path = os.path.join(solr_path, "example", "start.jar")
    if not os.path.isfile(start_jar_path):
        raise Exception("start.jar at '%s' was not found." % start_jar_path)

    if tcp_port_is_open(port=port):
        raise Exception("Port %d is already open on this machine." % port)

    solr_webapp_path = os.path.abspath(os.path.join(solr_path, "example", "solr-webapp"))
    if not os.path.isdir(solr_webapp_path):
        raise Exception("Solr webapp dir at '%s' was not found." % solr_webapp_path)

    logger.info("Starting Solr instance on port %d..." % port)

    args = ["java"]
    args += jvm_opts
    args = args + [
        "-server",
        "-Xmx" + jvm_heap_size_limit,
        "-Djava.util.logging.config.file=file://" + os.path.abspath(log4j_properties_path),
        "-Djetty.home=%s" % instance_data_dir,
        "-Djetty.port=%d" % port,
        "-Dsolr.solr.home=%s" % instance_data_dir,
        "-Dsolr.data.dir=%s" % instance_data_dir,
        "-Dmediacloud.luceneMatchVersion=%s" % MC_SOLR_LUCENEMATCHVERSION,

        # needed for resolving paths to JARs in solrconfig.xml
        "-Dmediacloud.solr_dist_dir=%s" % solr_path,
        "-Dmediacloud.solr_webapp_dir=%s" % solr_webapp_path,
    ]
    args = args + start_jar_args
    args = args + [
        "-jar", start_jar_path,
    ]

    logger.debug("Running command: %s" % ' '.join(args))
    subprocess.check_call(args)


def run_solr_shard(shard_num,
                   shard_count,
                   starting_port=MC_SOLR_CLUSTER_STARTING_PORT,
                   data_dir=MC_SOLR_DATA_DIR,
                   jvm_heap_size_limit=MC_SOLR_JVM_HEAP_SIZE_LIMIT,
                   dist_directory=MC_DIST_DIR,
                   solr_version=MC_SOLR_VERSION,
                   zookeeper_host=MC_SOLR_CLUSTER_ZOOKEEPER_HOST,
                   zookeeper_port=MC_SOLR_CLUSTER_ZOOKEEPER_PORT):
    """Run Solr shard, install Solr if needed; read configuration from ZooKeeper."""
    if shard_num < 0:
        raise Exception("Shard number must be 1 or greater.")
    if shard_count < 0:
        raise Exception("Shard count must be 1 or greater.")

    if not __solr_is_installed():
        logger.info("Solr is not installed, installing...")
        __install_solr()

    shard_name = __shard_name(shard_num=shard_num)
    shard_port = __shard_port(shard_num=shard_num, starting_port=starting_port)
    shard_data_dir = __shard_data_dir(shard_num=shard_num, data_dir=data_dir)

    data_dir = os.path.abspath(data_dir)
    if not os.path.isdir(data_dir):
        raise Exception("Solr data directory '%s' does not exist." % data_dir)

    logger.info("Waiting for ZooKeeper to start on %s:%d..." % (zookeeper_host, zookeeper_port))
    while not tcp_port_is_open(hostname=zookeeper_host, port=zookeeper_port):
        logger.info("ZooKeeper still not up.")
        time.sleep(1)
    logger.info("ZooKeeper is up!")

    logger.info("Starting Solr shard '%s' on port %d..." % (shard_name, shard_port))
    shard_args = [
        "-Dhost=%s" % shard_name,
        "-DzkHost=%s:%d" % (zookeeper_host, zookeeper_port),
        "-DnumShards=%d" % shard_count,
    ]
    run_solr(port=shard_port,
             instance_data_dir=shard_data_dir,
             jvm_opts=MC_SOLR_CLUSTER_JVM_OPTS,
             start_jar_args=shard_args,
             jvm_heap_size_limit=jvm_heap_size_limit,
             dist_directory=dist_directory,
             solr_version=solr_version)


def reload_solr_shard(shard_num,
                      host="localhost",
                      starting_port=MC_SOLR_CLUSTER_STARTING_PORT):
    """Reload Solr shard after ZooKeeper configuration change."""
    if shard_num < 0:
        raise Exception("Shard number must be 1 or greater.")

    shard_port = __shard_port(shard_num=shard_num, starting_port=starting_port)

    if not tcp_port_is_open(hostname=host, port=shard_port):
        raise Exception("Shard %d is not running on %s:%d." % (shard_num, host, shard_port))

    logger.info("Reloading shard %d on %s:%d..." % (shard_num, host, shard_port))

    collections = __solr_collections()
    logger.debug("Solr collections: %s" % collections)

    for collection_name, collection_path in sorted(collections.items()):
        logger.info("Reloading collection '%s' on shard %d on %s:%d..." % (
            collection_name, shard_num, host, shard_port
        ))
        url = "http://%(host)s:%(port)d/solr/admin/cores?action=RELOAD&core=%(collection_name)s" % {
            "host": host,
            "port": shard_port,
            "collection_name": collection_name,
        }
        logger.debug("Requesting URL %s..." % url)

        try:
            urllib2.urlopen(url)
        except urllib2.URLError as e:
            raise Exception("Unable to reload shard %d on %s:%d: %s" % (shard_num, host, shard_port, e.reason))

    logger.info("Reloaded shard %d on %s:%d." % (shard_num, host, shard_port))


def reload_all_solr_shards(shard_count,
                           host="localhost",
                           starting_port=MC_SOLR_CLUSTER_STARTING_PORT):
    """Reload all Solr shards after ZooKeeper configuration change."""
    if shard_count < 0:
        raise Exception("Shard count must be 1 or greater.")

    logger.info("Reloading %d shards on %s..." % (shard_count, host))
    for shard_num in range(1, shard_count + 1):
        reload_solr_shard(shard_num=shard_num, host=host, starting_port=starting_port)
    logger.info("Reloaded %d shards on %s." % (shard_count, host))
