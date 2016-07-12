import atexit

import signal

from mc_solr.constants import *
from mc_solr.distpath import distribution_path
import mc_solr.solr
from mc_solr.utils import *

logger = create_logger(__name__)

zookeeper_pid = None


def __zookeeper_path(dist_directory=MC_DIST_DIR, zookeeper_version=MC_ZOOKEEPER_VERSION):
    """Return path to where ZooKeeper distribution should be located."""
    dist_path = distribution_path(dist_directory=dist_directory)
    zookeeper_directory = "zookeeper-%s" % zookeeper_version
    solr_path = os.path.join(dist_path, zookeeper_directory)
    return solr_path


def __zookeeper_installing_file_path(dist_directory=MC_DIST_DIR, zookeeper_version=MC_ZOOKEEPER_VERSION):
    """Return path to file which denotes that ZooKeeper is being installed (and thus serves as a lock file)."""
    zookeeper_path = __zookeeper_path(dist_directory=dist_directory, zookeeper_version=zookeeper_version)
    return os.path.join(zookeeper_path, MC_PACKAGE_INSTALLING_FILE)


def __zookeeper_installed_file_path(dist_directory=MC_DIST_DIR, zookeeper_version=MC_ZOOKEEPER_VERSION):
    """Return path to file which denotes that ZooKeeper has been installed."""
    zookeeper_path = __zookeeper_path(dist_directory=dist_directory, zookeeper_version=zookeeper_version)
    return os.path.join(zookeeper_path, MC_PACKAGE_INSTALLED_FILE)


def __zookeeper_is_installed(dist_directory=MC_DIST_DIR, zookeeper_version=MC_ZOOKEEPER_VERSION):
    """Return True if ZooKeeper is installed in distribution path."""
    zookeeper_path = __zookeeper_path(dist_directory=dist_directory, zookeeper_version=zookeeper_version)
    installed_file_path = __zookeeper_installed_file_path(dist_directory=dist_directory,
                                                          zookeeper_version=zookeeper_version)

    if os.path.isfile(installed_file_path):
        if os.path.isfile(os.path.join(zookeeper_path, "README.txt")):
            return True
        else:
            logger.warn(
                "ZooKeeper distribution was not found at path '%s' even though it was supposed to be there." %
                zookeeper_path)
            os.unlink(installed_file_path)

    return False


def __zookeeper_dist_url(zookeeper_version=MC_ZOOKEEPER_VERSION):
    """Return URL to download ZooKeeper from."""
    zookeeper_dist_url = ("https://archive.apache.org/dist/zookeeper/zookeeper-%(zookeeper_version)s/"
                          "zookeeper-%(zookeeper_version)s.tar.gz") % {
                             "zookeeper_version": zookeeper_version,
                         }
    return zookeeper_dist_url


def __install_zookeeper(dist_directory=MC_DIST_DIR, zookeeper_version=MC_ZOOKEEPER_VERSION):
    """Install ZooKeeper to distribution directory; lock directory before installing and unlock afterwards."""
    if __zookeeper_is_installed(dist_directory=dist_directory, zookeeper_version=zookeeper_version):
        raise Exception("ZooKeeper %s is already installed in distribution directory '%s'." % (
            zookeeper_version, dist_directory
        ))

    zookeeper_path = __zookeeper_path(dist_directory=dist_directory, zookeeper_version=zookeeper_version)

    logger.info("Creating ZooKeeper directory...")
    mkdir_p(zookeeper_path)

    installing_file_path = __zookeeper_installing_file_path(dist_directory=dist_directory,
                                                            zookeeper_version=zookeeper_version)

    logger.info("Locking ZooKeeper directory for installation...")
    lock_file(installing_file_path, timeout=MC_INSTALL_TIMEOUT)

    # Waited for concurrent installation to finish?
    if __zookeeper_is_installed(dist_directory=dist_directory, zookeeper_version=zookeeper_version):
        logger.info("While waiting for ZooKeeper directory to unlock, ZooKeeper got installed to said directory.")
        return

    zookeeper_dist_url = __zookeeper_dist_url(zookeeper_version=zookeeper_version)

    logger.info("Downloading ZooKeeper %s from %s..." % (zookeeper_version, zookeeper_dist_url))
    zookeeper_tarball_dest_path = download_file_to_temp_path(source_url=zookeeper_dist_url)

    logger.info("Extracting %s to %s..." % (zookeeper_tarball_dest_path, zookeeper_path))
    extract_tarball_to_directory(archive_file=zookeeper_tarball_dest_path,
                                 dest_directory=zookeeper_path,
                                 strip_root=True)

    logger.info("Creating 'installed' file...")
    installed_file_path = __zookeeper_installed_file_path(dist_directory=dist_directory,
                                                          zookeeper_version=zookeeper_version)
    lock_file(installed_file_path)

    logger.info("Removing lock file...")
    unlock_file(installing_file_path)

    if not __zookeeper_is_installed(dist_directory=dist_directory, zookeeper_version=zookeeper_version):
        raise Exception("I've done everything but ZooKeeper is still not installed.")


def zookeeper_solr_config_updated_file(data_dir=MC_ZOOKEEPER_DATA_DIR):
    """Return path to file which denotes that Solr's configuration has been uploaded successfully."""
    data_dir = os.path.abspath(data_dir)
    if not os.path.isdir(data_dir):
        raise Exception("ZooKeeper data directory '%s' does not exist." % data_dir)
    return os.path.join(data_dir, MC_ZOOKEEPER_SOLR_CONFIG_UPDATED_FILE)


def __kill_zookeeper():
    """Kill ZooKeeper on exit."""
    global zookeeper_pid
    if zookeeper_pid is not None:
        os.kill(zookeeper_pid, signal.SIGTERM)


def run_zookeeper(dist_directory=MC_DIST_DIR,
                  zookeeper_version=MC_ZOOKEEPER_VERSION,
                  listen=MC_ZOOKEEPER_LISTEN,
                  port=MC_ZOOKEEPER_PORT,
                  data_dir=MC_ZOOKEEPER_DATA_DIR):
    solr_config_updated_file = zookeeper_solr_config_updated_file(data_dir=data_dir)
    if os.path.isfile(solr_config_updated_file):
        logger.info("Removing 'Solr config was updated' file at %s" % solr_config_updated_file)
        os.unlink(solr_config_updated_file)

    """Run ZooKeeper, install if needed too."""
    if not __zookeeper_is_installed():
        logger.info("ZooKeeper is not installed, installing...")
        __install_zookeeper()

    collections = mc_solr.solr.solr_collections()
    logger.debug("Solr collections: %s" % collections)

    # Needed for ZkCLI
    if not mc_solr.solr.solr_is_installed():
        logger.info("Solr is not installed, installing...")
        mc_solr.solr.install_solr()

    data_dir = os.path.abspath(data_dir)
    if not os.path.isdir(data_dir):
        raise Exception("ZooKeeper data directory '%s' does not exist." % data_dir)

    if tcp_port_is_open(port=port):
        raise Exception("Port %d is already open on this machine." % port)

    zookeeper_path = __zookeeper_path(dist_directory=dist_directory, zookeeper_version=zookeeper_version)

    zkserver_path = os.path.join(zookeeper_path, "bin", "zkServer.sh")
    if not os.path.isfile(zkserver_path):
        raise Exception("zkServer.sh at '%s' was not found." % zkserver_path)

    log4j_properties_path = os.path.join(zookeeper_path, "conf", "log4j.properties")
    if not os.path.isfile(log4j_properties_path):
        raise Exception("log4j.properties at '%s' was not found.")

    zoo_cnf_path = os.path.join(data_dir, "zoo.cfg")
    logger.info("Creating zoo.cfg in '%s'" % zoo_cnf_path)

    with open(zoo_cnf_path, 'w') as zoo_cnf:
        zoo_cnf.write("""
#
# This file is autogenerated. Please do not modify it!
#

clientPortAddress=%(listen)s
clientPort=%(port)d
dataDir=%(data_dir)s

tickTime=2000
initLimit=10
syncLimit=5
            """ % {
            "listen": listen,
            "port": port,
            "data_dir": data_dir,
        })

    zookeeper_env = os.environ.copy()
    zookeeper_env["ZOOCFGDIR"] = data_dir  # Serves as configuration dir too
    zookeeper_env["ZOOCFG"] = "zoo.cfg"
    zookeeper_env["ZOO_LOG_DIR"] = data_dir
    zookeeper_env["SERVER_JVMFLAGS"] = "-Dlog4j.configuration=file://" + os.path.abspath(log4j_properties_path)

    args = [
        zkserver_path,
        "start-foreground"
    ]

    logger.info("Starting ZooKeeper on %s:%d..." % (listen, port))
    logger.debug("Running command: %s" % ' '.join(args))
    logger.debug("Environment variables: %s" % ' '.join(zookeeper_env))

    process = subprocess.Popen(args, env=zookeeper_env)

    global zookeeper_pid
    zookeeper_pid = process.pid

    logger.info("ZooKeeper PID: %d" % zookeeper_pid)
    atexit.register(__kill_zookeeper)

    logger.info("Waiting for ZooKeeper to start at port %d..." % port)
    zookeeper_started = wait_for_tcp_port_to_open(port=port)
    if not zookeeper_started:
        raise Exception("Unable to connect to ZooKeeper at port %d" % port)

    logger.info("Uploading Solr collection configurations to ZooKeeper...")
    for collection_name, collection_path in sorted(collections.items()):
        collection_conf_path = os.path.join(collection_path, "conf")

        logger.info("Uploading collection's '%s' configuration at '%s'..." % (collection_name, collection_conf_path))
        mc_solr.solr.run_solr_zkcli([
            "-zkhost", "localhost:" + str(port),
            "-cmd", "upconfig",
            "-confdir", collection_conf_path,
            "-confname", collection_name,
        ])

        logger.info("Linking collection's '%s' configuration..." % collection_name)
        mc_solr.solr.run_solr_zkcli([
            "-zkhost", "localhost:" + str(port),
            "-cmd", "linkconfig",
            "-collection", collection_name,
            "-confname", collection_name,
        ])

    logger.info("Creating 'Solr config was updated' file at %s..." % solr_config_updated_file)
    lock_file(solr_config_updated_file)

    logger.info("ZooKeeper is ready!")
    while True:
        time.sleep(1)
