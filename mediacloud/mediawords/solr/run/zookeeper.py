import atexit
import os
import signal
import subprocess
import sys
import time

from mediawords.solr.run.constants import (
    MC_DIST_DIR, MC_ZOOKEEPER_VERSION, MC_PACKAGE_INSTALLING_FILE, MC_PACKAGE_INSTALLED_FILE,
    MC_INSTALL_TIMEOUT, MC_ZOOKEEPER_SIGKILL_TIMEOUT, MC_ZOOKEEPER_LISTEN, MC_ZOOKEEPER_PORT,
    MC_SOLR_BASE_DATA_DIR, MC_SOLR_VERSION, MC_ZOOKEEPER_CONNECT_RETRIES)
from mediawords.solr.run.solr import update_zookeeper_solr_configuration
from mediawords.util.compress import extract_tarball_to_directory
from mediawords.util.log import create_logger
from mediawords.util.network import wait_for_tcp_port_to_open, tcp_port_is_open
from mediawords.util.paths import mkdir_p, resolve_absolute_path_under_mc_root, lock_file, unlock_file
from mediawords.util.process import gracefully_kill_child_process
from mediawords.util.web import download_file_to_temp_path

log = create_logger(__name__)

__zookeeper_pid = None


class McZooKeeperRunException(Exception):
    """Exception of running ZooKeeper."""
    pass


def __zookeeper_path(dist_directory: str = MC_DIST_DIR,
                     zookeeper_version: str = MC_ZOOKEEPER_VERSION) -> str:
    """Return path to where ZooKeeper distribution should be located."""
    dist_path = resolve_absolute_path_under_mc_root(path=dist_directory)
    zookeeper_directory = "zookeeper-%s" % zookeeper_version
    solr_path = os.path.join(dist_path, zookeeper_directory)
    return solr_path


def __zookeeper_installing_file_path(dist_directory: str = MC_DIST_DIR,
                                     zookeeper_version: str = MC_ZOOKEEPER_VERSION) -> str:
    """Return path to file which denotes that ZooKeeper is being installed (and thus serves as a lock file)."""
    zookeeper_path = __zookeeper_path(dist_directory=dist_directory, zookeeper_version=zookeeper_version)
    return os.path.join(zookeeper_path, MC_PACKAGE_INSTALLING_FILE)


def __zookeeper_installed_file_path(dist_directory: str = MC_DIST_DIR,
                                    zookeeper_version: str = MC_ZOOKEEPER_VERSION) -> str:
    """Return path to file which denotes that ZooKeeper has been installed."""
    zookeeper_path = __zookeeper_path(dist_directory=dist_directory, zookeeper_version=zookeeper_version)
    return os.path.join(zookeeper_path, MC_PACKAGE_INSTALLED_FILE)


def __zookeeper_is_installed(dist_directory: str = MC_DIST_DIR, zookeeper_version: str = MC_ZOOKEEPER_VERSION) -> bool:
    """Return True if ZooKeeper is installed in distribution path."""
    zookeeper_path = __zookeeper_path(dist_directory=dist_directory, zookeeper_version=zookeeper_version)
    installed_file_path = __zookeeper_installed_file_path(dist_directory=dist_directory,
                                                          zookeeper_version=zookeeper_version)

    if os.path.isfile(installed_file_path):
        if os.path.isfile(os.path.join(zookeeper_path, "README.txt")):
            return True
        else:
            log.warning(
                "ZooKeeper distribution was not found at path '%s' even though it was supposed to be there." %
                zookeeper_path)
            os.unlink(installed_file_path)

    return False


def __zookeeper_dist_url(zookeeper_version: str = MC_ZOOKEEPER_VERSION) -> str:
    """Return URL to download ZooKeeper from."""
    zookeeper_dist_url = ("https://archive.apache.org/dist/zookeeper/zookeeper-%(zookeeper_version)s/"
                          "zookeeper-%(zookeeper_version)s.tar.gz") % {
                              "zookeeper_version": zookeeper_version,
    }
    return zookeeper_dist_url


def __install_zookeeper(dist_directory: str = MC_DIST_DIR, zookeeper_version: str = MC_ZOOKEEPER_VERSION) -> None:
    """Install ZooKeeper to distribution directory; lock directory before installing and unlock afterwards."""
    if __zookeeper_is_installed(dist_directory=dist_directory, zookeeper_version=zookeeper_version):
        raise McZooKeeperRunException("ZooKeeper %s is already installed in distribution directory '%s'." % (
            zookeeper_version, dist_directory
        ))

    zookeeper_path = __zookeeper_path(dist_directory=dist_directory, zookeeper_version=zookeeper_version)

    log.info("Creating ZooKeeper directory...")
    mkdir_p(zookeeper_path)

    installing_file_path = __zookeeper_installing_file_path(dist_directory=dist_directory,
                                                            zookeeper_version=zookeeper_version)

    log.info("Locking ZooKeeper directory for installation...")
    lock_file(installing_file_path, timeout=MC_INSTALL_TIMEOUT)

    # Waited for concurrent installation to finish?
    if __zookeeper_is_installed(dist_directory=dist_directory, zookeeper_version=zookeeper_version):
        log.info("While waiting for ZooKeeper directory to unlock, ZooKeeper got installed to said directory.")
        return

    zookeeper_dist_url = __zookeeper_dist_url(zookeeper_version=zookeeper_version)

    log.info("Downloading ZooKeeper %s from %s..." % (zookeeper_version, zookeeper_dist_url))
    zookeeper_tarball_dest_path = download_file_to_temp_path(source_url=zookeeper_dist_url)

    log.info("Extracting %s to %s..." % (zookeeper_tarball_dest_path, zookeeper_path))
    extract_tarball_to_directory(archive_file=zookeeper_tarball_dest_path,
                                 dest_directory=zookeeper_path,
                                 strip_root=True)

    log.info("Creating 'installed' file...")
    installed_file_path = __zookeeper_installed_file_path(dist_directory=dist_directory,
                                                          zookeeper_version=zookeeper_version)
    lock_file(installed_file_path)

    log.info("Removing lock file...")
    unlock_file(installing_file_path)

    if not __zookeeper_is_installed(dist_directory=dist_directory, zookeeper_version=zookeeper_version):
        raise McZooKeeperRunException("I've done everything but ZooKeeper is still not installed.")


# noinspection PyUnusedLocal
def __kill_zookeeper_process(signum: int = None, frame: int = None) -> None:
    """Pass SIGINT/SIGTERM to child ZooKeeper when exiting."""
    global __zookeeper_pid
    if __zookeeper_pid is None:
        log.warning("ZooKeeper PID is unset, probably it wasn't started.")
    else:
        gracefully_kill_child_process(child_pid=__zookeeper_pid, sigkill_timeout=MC_ZOOKEEPER_SIGKILL_TIMEOUT)
    sys.exit(signum or 0)


def run_zookeeper(dist_directory: str = MC_DIST_DIR,
                  listen: str = MC_ZOOKEEPER_LISTEN,
                  port: int = MC_ZOOKEEPER_PORT,
                  data_dir: str = MC_SOLR_BASE_DATA_DIR,
                  zookeeper_version: str = MC_ZOOKEEPER_VERSION,
                  solr_version: str = MC_SOLR_VERSION) -> None:
    """Run ZooKeeper, install if needed too."""
    if not __zookeeper_is_installed():
        log.info("ZooKeeper is not installed, installing...")
        __install_zookeeper()

    data_dir = resolve_absolute_path_under_mc_root(path=data_dir, must_exist=True)

    zookeeper_data_dir = os.path.join(data_dir, "mediacloud-cluster-zookeeper")
    if not os.path.isdir(zookeeper_data_dir):
        log.info("Creating data directory at %s..." % zookeeper_data_dir)
        mkdir_p(zookeeper_data_dir)

    if tcp_port_is_open(port=port):
        raise McZooKeeperRunException("Port %d is already open on this machine." % port)

    zookeeper_path = __zookeeper_path(dist_directory=dist_directory, zookeeper_version=zookeeper_version)

    zkserver_path = os.path.join(zookeeper_path, "bin", "zkServer.sh")
    if not os.path.isfile(zkserver_path):
        raise McZooKeeperRunException("zkServer.sh at '%s' was not found." % zkserver_path)

    log4j_properties_path = os.path.join(zookeeper_path, "conf", "log4j.properties")
    if not os.path.isfile(log4j_properties_path):
        raise McZooKeeperRunException("log4j.properties at '%s' was not found.")

    zoo_cnf_path = os.path.join(zookeeper_data_dir, "zoo.cfg")
    log.info("Creating zoo.cfg in '%s'..." % zoo_cnf_path)

    with open(zoo_cnf_path, 'w') as zoo_cnf:
        zoo_cnf.write("""
#
# This file is autogenerated. Please do not modify it!
#

clientPortAddress=%(listen)s
clientPort=%(port)d
dataDir=%(data_dir)s

# Must be between zkClientTimeout / 2 and zkClientTimeout / 20
tickTime=30000

initLimit=10
syncLimit=10
            """ % {
            "listen": listen,
            "port": port,
            "data_dir": zookeeper_data_dir,
        })

    zookeeper_env = os.environ.copy()
    zookeeper_env["ZOOCFGDIR"] = zookeeper_data_dir  # Serves as configuration dir too
    zookeeper_env["ZOOCFG"] = "zoo.cfg"
    zookeeper_env["ZOO_LOG_DIR"] = zookeeper_data_dir
    zookeeper_env["SERVER_JVMFLAGS"] = "-Dlog4j.configuration=file://" + os.path.abspath(log4j_properties_path)

    args = [
        zkserver_path,
        "start-foreground"
    ]

    log.info("Starting ZooKeeper on %s:%d..." % (listen, port))
    log.debug("Running command: %s" % str(args))
    log.debug("Environment variables: %s" % str(zookeeper_env))

    process = subprocess.Popen(args, env=zookeeper_env)
    global __zookeeper_pid
    __zookeeper_pid = process.pid

    # Declare that we don't care about the exit code of the child process so
    # it doesn't become a zombie when it gets killed in signal handler
    signal.signal(signal.SIGCHLD, signal.SIG_IGN)

    signal.signal(signal.SIGTERM, __kill_zookeeper_process)  # SIGTERM is handled differently for whatever reason
    atexit.register(__kill_zookeeper_process)

    log.info("ZooKeeper PID: %d" % __zookeeper_pid)

    log.info("Waiting for ZooKeeper to start at port %d..." % port)
    zookeeper_started = wait_for_tcp_port_to_open(port=port, retries=MC_ZOOKEEPER_CONNECT_RETRIES)
    if not zookeeper_started:
        raise McZooKeeperRunException("Unable to connect to ZooKeeper at port %d" % port)

    log.info("Uploading initial Solr collection configurations to ZooKeeper...")
    update_zookeeper_solr_configuration(zookeeper_host="localhost",
                                        zookeeper_port=port,
                                        dist_directory=dist_directory,
                                        solr_version=solr_version)

    log.info("ZooKeeper is ready on port %d!" % port)
    while True:
        time.sleep(1)
