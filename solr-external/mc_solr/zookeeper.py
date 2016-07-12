import atexit

from mc_solr.constants import *
from mc_solr.path import resolve_absolute_path
import mc_solr.solr
from mc_solr.utils import *

logger = create_logger(__name__)


def __zookeeper_path(dist_directory=MC_DIST_DIR, zookeeper_version=MC_ZOOKEEPER_VERSION):
    """Return path to where ZooKeeper distribution should be located."""
    dist_path = resolve_absolute_path(name=dist_directory)
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


def run_zookeeper(dist_directory=MC_DIST_DIR,
                  listen=MC_ZOOKEEPER_LISTEN,
                  port=MC_ZOOKEEPER_PORT,
                  data_dir=MC_ZOOKEEPER_DATA_DIR,
                  zookeeper_version=MC_ZOOKEEPER_VERSION,
                  solr_version=MC_SOLR_VERSION):
    """Run ZooKeeper, install if needed too."""
    if not __zookeeper_is_installed():
        logger.info("ZooKeeper is not installed, installing...")
        __install_zookeeper()

    data_dir = resolve_absolute_path(name=data_dir, must_exist=True)

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

    @atexit.register
    def __kill_zookeeper_process():
        print("Trying to terminate ZooKeeper at PID %d..." % process.pid)
        process.terminate()

    logger.info("ZooKeeper PID: %d" % process.pid)

    logger.info("Waiting for ZooKeeper to start at port %d..." % port)
    zookeeper_started = wait_for_tcp_port_to_open(port=port)
    if not zookeeper_started:
        raise Exception("Unable to connect to ZooKeeper at port %d" % port)

    logger.info("Uploading initial Solr collection configurations to ZooKeeper...")
    mc_solr.solr.update_zookeeper_solr_configuration(zookeeper_host="localhost",
                                                     zookeeper_port=port,
                                                     dist_directory=dist_directory,
                                                     solr_version=solr_version)

    logger.info("ZooKeeper is ready!")
    while True:
        time.sleep(1)
