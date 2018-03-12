import atexit
import glob
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from typing import Dict, List
from urllib.error import URLError
from urllib.request import urlopen

from mediawords.solr.run.constants import (
    MC_DIST_DIR, MC_SOLR_VERSION, MC_PACKAGE_INSTALLING_FILE, MC_PACKAGE_INSTALLED_FILE,
    MC_INSTALL_TIMEOUT, MC_SOLR_HOME_DIR, MC_SOLR_BASE_DATA_DIR, MC_SOLR_CLUSTER_STARTING_PORT,
    MC_SOLR_CLUSTER_ZOOKEEPER_HOST, MC_SOLR_CLUSTER_ZOOKEEPER_PORT, MC_SOLR_CLUSTER_ZOOKEEPER_TIMEOUT,
    MC_SOLR_SIGKILL_TIMEOUT, MC_SOLR_STANDALONE_JVM_OPTS, MC_SOLR_LUCENEMATCHVERSION, MC_SOLR_STANDALONE_PORT,
    MC_SOLR_STANDALONE_JVM_HEAP_SIZE, MC_SOLR_STANDALONE_CONNECT_RETRIES,
    MC_SOLR_CLUSTER_JVM_HEAP_SIZE, MC_SOLR_CLUSTER_ZOOKEEPER_CONNECT_RETRIES,
    MC_SOLR_CLUSTER_JVM_OPTS, MC_SOLR_CLUSTER_CONNECT_RETRIES)
from mediawords.util.compress import extract_tarball_to_directory
from mediawords.util.log import create_logger
from mediawords.util.network import fqdn, hostname_resolves, wait_for_tcp_port_to_open, tcp_port_is_open
from mediawords.util.paths import mkdir_p, resolve_absolute_path_under_mc_root, relative_symlink, lock_file, unlock_file
from mediawords.util.process import run_command_in_foreground, gracefully_kill_child_process
from mediawords.util.web import download_file_to_temp_path

log = create_logger(__name__)

__solr_pid = None


class McSolrRunException(Exception):
    """Exception of running Solr."""
    pass


def __solr_path(dist_directory: str = MC_DIST_DIR, solr_version: str = MC_SOLR_VERSION) -> str:
    """Return path to where Solr distribution should be located."""
    dist_path = resolve_absolute_path_under_mc_root(path=dist_directory, must_exist=True)
    solr_directory = "solr-%s" % solr_version
    solr_path = os.path.join(dist_path, solr_directory)
    return solr_path


def __solr_installing_file_path(dist_directory: str = MC_DIST_DIR, solr_version: str = MC_SOLR_VERSION) -> str:
    """Return path to file which denotes that Solr is being installed (and thus serves as a lock file)."""
    solr_path = __solr_path(dist_directory=dist_directory, solr_version=solr_version)
    return os.path.join(solr_path, MC_PACKAGE_INSTALLING_FILE)


def __solr_installed_file_path(dist_directory: str = MC_DIST_DIR, solr_version: str = MC_SOLR_VERSION) -> str:
    """Return path to file which denotes that Solr has been installed."""
    solr_path = __solr_path(dist_directory=dist_directory, solr_version=solr_version)
    return os.path.join(solr_path, MC_PACKAGE_INSTALLED_FILE)


def __solr_dist_url(solr_version: str = MC_SOLR_VERSION) -> str:
    """Return URL to download Solr from."""
    solr_dist_url = "https://archive.apache.org/dist/lucene/solr/%(solr_version)s/solr-%(solr_version)s.tgz" % {
        "solr_version": solr_version,
    }
    return solr_dist_url


def __solr_is_installed(dist_directory: str = MC_DIST_DIR, solr_version: str = MC_SOLR_VERSION) -> bool:
    """Return True if Solr is installed in distribution path."""
    solr_path = __solr_path(dist_directory=dist_directory, solr_version=solr_version)
    installed_file_path = __solr_installed_file_path(dist_directory=dist_directory, solr_version=solr_version)

    if os.path.isfile(installed_file_path):
        if os.path.isfile(os.path.join(solr_path, "README.txt")):
            return True
        else:
            log.warning(
                "Solr distribution was not found at path '%s' even though it was supposed to be there." % solr_path)
            os.unlink(installed_file_path)

    return False


def __install_solr(dist_directory: str = MC_DIST_DIR, solr_version: str = MC_SOLR_VERSION) -> None:
    """Install Solr to distribution directory; lock directory before installing and unlock afterwards."""
    if __solr_is_installed(dist_directory=dist_directory, solr_version=solr_version):
        raise McSolrRunException("Solr %s is already installed in distribution directory '%s'." % (
            solr_version, dist_directory
        ))

    solr_path = __solr_path(dist_directory=dist_directory, solr_version=solr_version)

    log.info("Creating Solr directory...")
    mkdir_p(solr_path)

    installing_file_path = __solr_installing_file_path(dist_directory=dist_directory, solr_version=solr_version)

    log.info("Locking Solr directory for installation...")
    lock_file(installing_file_path, timeout=MC_INSTALL_TIMEOUT)

    # Waited for concurrent installation to finish?
    if __solr_is_installed(dist_directory=dist_directory, solr_version=solr_version):
        log.info("While waiting for Solr directory to unlock, Solr got installed to said directory.")
        return

    solr_dist_url = __solr_dist_url(solr_version=solr_version)

    log.info("Downloading Solr %s from %s..." % (solr_version, solr_dist_url))
    solr_tarball_dest_path = download_file_to_temp_path(solr_dist_url)

    log.info("Extracting %s to %s..." % (solr_tarball_dest_path, solr_path))
    extract_tarball_to_directory(archive_file=solr_tarball_dest_path,
                                 dest_directory=solr_path,
                                 strip_root=True)

    # Solr needs its .war extracted first before ZkCLI is usable
    jetty_home_path = __jetty_home_path(dist_directory=dist_directory, solr_version=solr_version)

    solr_war_dest_dir = os.path.join(jetty_home_path, "solr-webapp", "webapp")
    if not os.path.exists(os.path.join(solr_war_dest_dir, "index.html")):
        raise McSolrRunException("Solr's .war is not extracted at path %s" % solr_war_dest_dir)

    log.info("Creating 'installed' file...")
    installed_file_path = __solr_installed_file_path(dist_directory=dist_directory, solr_version=solr_version)
    lock_file(installed_file_path)

    log.info("Removing lock file...")
    unlock_file(installing_file_path)

    if not __solr_is_installed(dist_directory=dist_directory, solr_version=solr_version):
        raise McSolrRunException("I've done everything but Solr is still not installed.")


def __solr_home_path(solr_home_dir: str = MC_SOLR_HOME_DIR) -> str:
    """Return path to Solr home (with collection subdirectories)."""
    solr_home_path = resolve_absolute_path_under_mc_root(path=solr_home_dir, must_exist=True)
    return solr_home_path


def __jetty_home_path(dist_directory: str = MC_DIST_DIR, solr_version: str = MC_SOLR_VERSION) -> str:
    solr_path = __solr_path(dist_directory=dist_directory, solr_version=solr_version)

    jetty_home_path = os.path.join(solr_path, "server")
    if not os.path.exists(os.path.join(jetty_home_path, "start.jar")):
        raise McSolrRunException("Unable to locate jetty.home: %s" % jetty_home_path)

    return jetty_home_path


def __collections_path(solr_home_dir: str = MC_SOLR_HOME_DIR) -> str:
    solr_home_path = __solr_home_path(solr_home_dir=solr_home_dir)
    collections_path = os.path.join(solr_home_path, "collections/")
    if not os.path.isdir(collections_path):
        raise McSolrRunException("Collections directory does not exist at path '%s'" % collections_path)
    log.debug("Collections path: %s" % collections_path)
    return collections_path


def __collections(solr_home_dir: str = MC_SOLR_HOME_DIR) -> Dict[str, str]:
    """Return dictionary with names and absolute paths to Solr collections."""
    collections = {}
    collections_path = __collections_path(solr_home_dir)
    collection_names = os.listdir(collections_path)
    log.debug("Files in collections directory: %s" % collection_names)
    for name in collection_names:
        if not (name.startswith("_") or name.startswith(".")):
            full_path = os.path.join(collections_path, name)
            if os.path.isdir(full_path):

                collection_conf_path = os.path.join(full_path, "conf")
                if not os.path.isdir(collection_conf_path):
                    raise McSolrRunException("Collection configuration path for collection '%s' does not exist." % name)

                collections[name] = full_path

    return collections


def __standalone_data_dir(base_data_dir: str = MC_SOLR_BASE_DATA_DIR) -> str:
    """Return data directory for a standalone instance."""
    if not os.path.isdir(base_data_dir):
        raise McSolrRunException("Solr data directory '%s' does not exist." % base_data_dir)
    return os.path.join(base_data_dir, "mediacloud-standalone")


def __shard_data_dir(shard_num: int, base_data_dir: str = MC_SOLR_BASE_DATA_DIR) -> str:
    """Return data directory for a shard."""
    if shard_num < 1:
        raise McSolrRunException("Shard number must be 1 or greater.")
    if not os.path.isdir(base_data_dir):
        raise McSolrRunException("Solr data directory '%s' does not exist." % base_data_dir)

    shard_subdir = "mediacloud-cluster-shard-%d" % shard_num
    return os.path.join(base_data_dir, shard_subdir)


def __shard_port(shard_num: int, starting_port: int = MC_SOLR_CLUSTER_STARTING_PORT) -> int:
    """Return port on which a shard should listen to."""
    if shard_num < 1:
        raise McSolrRunException("Shard number must be 1 or greater.")
    return starting_port + shard_num - 1


def __raise_if_old_shards_exist() -> None:
    """Raise exception with migration instructions if old shard directories exist already."""

    pwd = resolve_absolute_path_under_mc_root(path=".")
    old_shards = glob.glob(pwd + "/mediacloud-shard-*")

    if len(old_shards) == 0:
        # No old shards to migrate
        return

    num_shards = 0
    for old_shard_path in old_shards:
        old_shard_dir = os.path.basename(old_shard_path)

        old_shard_num = re.search(r'^mediacloud-shard-(\d+?)$', old_shard_dir)
        if old_shard_num is None:
            raise McSolrRunException("Unable to parse shard number for old shard directory '%s'" % old_shard_dir)
        old_shard_num = int(old_shard_num.group(1))

        num_shards = max(num_shards, old_shard_num)

    exc_message = "Old shards were found at paths:\n\n"
    for old_shard_path in old_shards:
        exc_message += "* %s\n" % old_shard_path

    exc_message += "\n"
    exc_message += "Please migrate them by running:\n"
    exc_message += "\n"
    exc_message += "cd %s\n" % pwd
    exc_message += "\n"
    exc_message += "# Create empty new shard directory structure for each shard:\n"
    for shard_num in range(1, num_shards + 1):
        exc_message += ("./run_solr_shard.py --shard_num %(shard_num)d --shard_count %(shard_count)d "
                        "|| echo \"It's fine to fail at this point.\"\n") % {
                            "shard_num": shard_num,
                            "shard_count": num_shards,
        }

    exc_message += "\n"
    exc_message += "# Move data from old shards to new ones\n"
    for shard_num in range(1, num_shards + 1):
        shard_solr_path = "mediacloud-shard-%d/solr/" % shard_num
        shard_collection_paths = glob.glob(shard_solr_path + "/collection*")
        if len(shard_collection_paths) == 0:
            raise McSolrRunException("No collections found in shard '%d'" % shard_num)
        for collection_path in shard_collection_paths:
            collection_name = os.path.basename(collection_path)

            src_collection_data_path = os.path.join(shard_solr_path, collection_name, "data")
            if not os.path.isdir(src_collection_data_path):
                raise McSolrRunException("Source data directory '%s' does not exist." % src_collection_data_path)

            dst_shard_data_dir = __shard_data_dir(shard_num=shard_num)
            dst_collection_data_path = os.path.join(dst_shard_data_dir, collection_name, "data")
            if os.path.isdir(dst_collection_data_path):
                raise McSolrRunException("Destination data directory '%s' already exists." % dst_collection_data_path)

            exc_message += "mv %(src_collection_data_dir)s %(dst_collection_data_dir)s\n" % {
                "src_collection_data_dir": src_collection_data_path,
                "dst_collection_data_dir": dst_collection_data_path,
            }
        exc_message += "\n"

    exc_message += "# Remove old shards\n"
    for shard_num in range(1, num_shards + 1):
        exc_message += "rm -rf mediacloud-shard-%d/\n" % shard_num

    raise McSolrRunException(exc_message)


def __run_solr_zkcli(zkcli_args: List[str],
                     zookeeper_host: str = MC_SOLR_CLUSTER_ZOOKEEPER_HOST,
                     zookeeper_port: int = MC_SOLR_CLUSTER_ZOOKEEPER_PORT,
                     dist_directory: str = MC_DIST_DIR,
                     solr_version: str = MC_SOLR_VERSION) -> None:
    """Run Solr's zkcli.sh helper script."""
    solr_path = __solr_path(dist_directory=dist_directory, solr_version=solr_version)

    jetty_home_path = __jetty_home_path(dist_directory=dist_directory, solr_version=solr_version)
    log4j_properties_path = os.path.join(jetty_home_path, "scripts", "cloud-scripts", "log4j.properties")

    if not os.path.isfile(log4j_properties_path):
        raise McSolrRunException(
            "Unable to find log4j.properties file for zkcli.sh script at path: %s" %
            log4j_properties_path
        )

    if not tcp_port_is_open(hostname=zookeeper_host, port=zookeeper_port):
        raise McSolrRunException("ZooKeeper is not running at %s:%d." % (zookeeper_host, zookeeper_port))

    jetty_home_path = __jetty_home_path(dist_directory=dist_directory, solr_version=solr_version)

    zkhost = "%s:%d" % (zookeeper_host, zookeeper_port)

    java_classpath_dirs = [
        os.path.join(solr_path, "dist", "*"),
        os.path.join(jetty_home_path, "solr-webapp", "webapp", "WEB-INF", "lib", "*"),
        os.path.join(jetty_home_path, "lib", "ext", "*"),
    ]

    args = ["java",
            "-classpath", ":".join(java_classpath_dirs),
            "-Dlog4j.configuration=file://" + os.path.abspath(log4j_properties_path),
            "org.apache.solr.cloud.ZkCLI",
            "-zkhost", zkhost] + zkcli_args

    run_command_in_foreground(args)


def update_zookeeper_solr_configuration(zookeeper_host: str = MC_SOLR_CLUSTER_ZOOKEEPER_HOST,
                                        zookeeper_port: int = MC_SOLR_CLUSTER_ZOOKEEPER_PORT,
                                        dist_directory: str = MC_DIST_DIR,
                                        solr_version: str = MC_SOLR_VERSION) -> None:
    """Update Solr's configuration on ZooKeeper."""
    if not __solr_is_installed():
        log.info("Solr is not installed, installing...")
        __install_solr()

    if not tcp_port_is_open(hostname=zookeeper_host, port=zookeeper_port):
        raise McSolrRunException("ZooKeeper is not running at %s:%d." % (zookeeper_host, zookeeper_port))

    collections = __collections()
    log.debug("Solr collections: %s" % collections)

    log.info("Uploading Solr collection configurations to ZooKeeper...")
    for collection_name, collection_path in sorted(collections.items()):
        collection_conf_path = os.path.join(collection_path, "conf")

        # Copy configuration because ZooKeeper's uploader doesn't like symlinks
        log.info("Copying collection's '%s' configuration to a temporary directory..." % collection_name)
        collection_conf_temp_dir = os.path.join(tempfile.mkdtemp(), collection_name)
        shutil.copytree(collection_conf_path, collection_conf_temp_dir)

        log.info("Uploading collection's '%s' configuration at '%s'..." % (
            collection_name, collection_conf_temp_dir))
        __run_solr_zkcli(zkcli_args=["-cmd", "upconfig",
                                     "-confdir", collection_conf_temp_dir,
                                     "-confname", collection_name],
                         zookeeper_host=zookeeper_host,
                         zookeeper_port=zookeeper_port,
                         dist_directory=dist_directory,
                         solr_version=solr_version)

        log.info("Linking collection's '%s' configuration..." % collection_name)
        __run_solr_zkcli(zkcli_args=["-cmd", "linkconfig",
                                     "-collection", collection_name,
                                     "-confname", collection_name],
                         zookeeper_host=zookeeper_host,
                         zookeeper_port=zookeeper_port,
                         dist_directory=dist_directory,
                         solr_version=solr_version)

    log.info("Uploaded Solr collection configurations to ZooKeeper.")


# noinspection PyUnusedLocal
def __kill_solr_process(signum: int = None, frame: int = None) -> None:
    """Pass SIGINT/SIGTERM to child Solr when exiting."""
    global __solr_pid
    if __solr_pid is None:
        log.warning("Solr PID is unset, probably it wasn't started.")
    else:
        gracefully_kill_child_process(child_pid=__solr_pid, sigkill_timeout=MC_SOLR_SIGKILL_TIMEOUT)
    sys.exit(signum or 0)


def __run_solr(port: int,
               instance_data_dir: str,
               hostname: str = None,
               jvm_heap_size: str = None,
               start_jar_args: List[str] = None,
               jvm_opts: List[str] = None,
               connect_timeout: int = 120,
               dist_directory: str = MC_DIST_DIR,
               solr_version: str = MC_SOLR_VERSION) -> None:
    """Run Solr instance."""
    if hostname is None:
        hostname = fqdn()
    if jvm_opts is None:
        jvm_opts = MC_SOLR_STANDALONE_JVM_OPTS

    if start_jar_args is None:
        start_jar_args = []

    if not __solr_is_installed():
        log.info("Solr is not installed, installing...")
        __install_solr()

    solr_home_dir = __solr_home_path(solr_home_dir=MC_SOLR_HOME_DIR)
    if not os.path.isdir(solr_home_dir):
        raise McSolrRunException("Solr home directory '%s' does not exist." % solr_home_dir)

    solr_path = __solr_path(dist_directory=dist_directory, solr_version=solr_version)

    if not os.path.isdir(instance_data_dir):
        log.info("Creating data directory at %s..." % instance_data_dir)
        mkdir_p(instance_data_dir)

    log.info("Updating collections at %s..." % instance_data_dir)
    collections = __collections(solr_home_dir=solr_home_dir)
    for collection_name, collection_path in sorted(collections.items()):
        log.info("Updating collection '%s'..." % collection_name)

        collection_conf_src_dir = os.path.join(collection_path, "conf")
        if not os.path.isdir(collection_conf_src_dir):
            raise McSolrRunException("Configuration for collection '%s' at %s does not exist" % (
                collection_name, collection_conf_src_dir
            ))

        collection_dst_dir = os.path.join(instance_data_dir, collection_name)
        mkdir_p(collection_dst_dir)

        # Remove and copy configuration in case it has changed
        # (don't symlink because Solr 5.5+ doesn't like those)
        collection_conf_dst_dir = os.path.join(collection_dst_dir, "conf")
        if os.path.lexists(collection_conf_dst_dir):
            log.debug("Removing old collection configuration in '%s'..." % collection_conf_dst_dir)
            if os.path.islink(collection_conf_dst_dir):
                # Might still be a link from older Solr versions
                os.unlink(collection_conf_dst_dir)
            else:
                shutil.rmtree(collection_conf_dst_dir)

        log.info("Copying '%s' to '%s'..." % (collection_conf_src_dir, collection_conf_dst_dir))
        shutil.copytree(collection_conf_src_dir, collection_conf_dst_dir, symlinks=False)

        log.info("Updating core.properties for collection '%s'..." % collection_name)
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

    log.info("Symlinking shard configuration...")
    config_items_to_symlink = [
        "contexts",
        "etc",
        "modules",
        "resources",
        "solr.xml",
    ]
    for config_item in config_items_to_symlink:
        config_item_src_path = os.path.join(solr_home_dir, config_item)
        if not os.path.exists(config_item_src_path):
            raise McSolrRunException("Expected configuration item '%s' does not exist" % config_item_src_path)

        # Recreate symlink just in case
        config_item_dst_path = os.path.join(instance_data_dir, config_item)
        if os.path.lexists(config_item_dst_path):
            if not os.path.islink(config_item_dst_path):
                raise McSolrRunException("Configuration item '%s' exists but is not a symlink." % config_item_dst_path)
            os.unlink(config_item_dst_path)

        log.info("Symlinking '%s' to '%s'..." % (config_item_src_path, config_item_dst_path))
        relative_symlink(config_item_src_path, config_item_dst_path)

    jetty_home_path = __jetty_home_path(dist_directory=dist_directory, solr_version=solr_version)

    log.info("Symlinking libraries and JARs...")
    library_items_to_symlink = [
        "lib",
        "solr-webapp",
        "start.jar",
        "solr",
        "solr-webapp",
    ]
    for library_item in library_items_to_symlink:
        library_item_src_path = os.path.join(jetty_home_path, library_item)
        if not os.path.exists(library_item_src_path):
            raise McSolrRunException("Expected library item '%s' does not exist" % library_item_src_path)

        # Recreate symlink just in case
        library_item_dst_path = os.path.join(instance_data_dir, library_item)
        if os.path.lexists(library_item_dst_path):
            if not os.path.islink(library_item_dst_path):
                raise McSolrRunException("Library item '%s' exists but is not a symlink." % library_item_dst_path)
            os.unlink(library_item_dst_path)

        log.info("Symlinking '%s' to '%s'..." % (library_item_src_path, library_item_dst_path))
        relative_symlink(library_item_src_path, library_item_dst_path)

    log4j_properties_path = os.path.join(solr_home_dir, "resources", "log4j.properties")
    if not os.path.isfile(log4j_properties_path):
        raise McSolrRunException("log4j.properties at '%s' was not found.")

    start_jar_path = os.path.join(jetty_home_path, "start.jar")
    if not os.path.isfile(start_jar_path):
        raise McSolrRunException("start.jar at '%s' was not found." % start_jar_path)

    solr_webapp_path = os.path.abspath(os.path.join(jetty_home_path, "solr-webapp"))
    if not os.path.isdir(solr_webapp_path):
        raise McSolrRunException("Solr webapp dir at '%s' was not found." % solr_webapp_path)

    if not hostname_resolves(hostname):
        raise McSolrRunException("Hostname '%s' does not resolve." % hostname)

    if tcp_port_is_open(port=port):
        raise McSolrRunException("Port %d is already open on this machine." % port)

    __raise_if_old_shards_exist()

    args = ["java"]
    log.info("Starting Solr instance on %s, port %d..." % (hostname, port))

    if jvm_heap_size is not None:
        args += ["-Xmx%s" % jvm_heap_size]
    args += jvm_opts
    # noinspection SpellCheckingInspection
    args += [
        "-server",
        "-Djava.util.logging.config.file=file://" + os.path.abspath(log4j_properties_path),
        "-Djetty.base=%s" % instance_data_dir,
        "-Djetty.home=%s" % instance_data_dir,
        "-Djetty.port=%d" % port,
        "-Dsolr.solr.home=%s" % instance_data_dir,
        "-Dsolr.data.dir=%s" % instance_data_dir,
        "-Dhost=%s" % hostname,
        "-DzkClientTimeout=%s" % MC_SOLR_CLUSTER_ZOOKEEPER_TIMEOUT,
        "-Dmediacloud.luceneMatchVersion=%s" % MC_SOLR_LUCENEMATCHVERSION,

        # write heap dump to data directory on OOM errors
        "-XX:+HeapDumpOnOutOfMemoryError",
        "-XX:HeapDumpPath=%s" % instance_data_dir,

        # needed for resolving paths to JARs in solrconfig.xml
        "-Dmediacloud.solr_dist_dir=%s" % solr_path,
        "-Dmediacloud.solr_webapp_dir=%s" % solr_webapp_path,

        # Remediate CVE-2017-12629
        "-Ddisable.configEdit=true",
    ]
    args += start_jar_args
    args += [
        "-jar", start_jar_path,
        "--module=http",
    ]

    log.debug("Running command: %s" % ' '.join(args))

    process = subprocess.Popen(args)
    global __solr_pid
    __solr_pid = process.pid

    # Declare that we don't care about the exit code of the child process so
    # it doesn't become a zombie when it gets killed in signal handler
    signal.signal(signal.SIGCHLD, signal.SIG_IGN)

    signal.signal(signal.SIGTERM, __kill_solr_process)  # SIGTERM is handled differently for whatever reason
    atexit.register(__kill_solr_process)

    log.info("Solr PID: %d" % __solr_pid)

    log.info("Solr is starting on port %d, will be available shortly..." % port)
    wait_for_tcp_port_to_open(port=port, retries=connect_timeout)

    log.info("Solr is running on port %d!" % port)
    while True:
        time.sleep(1)


def run_solr_standalone(hostname: str = None,
                        port: int = MC_SOLR_STANDALONE_PORT,
                        base_data_dir: str = MC_SOLR_BASE_DATA_DIR,
                        dist_directory: str = MC_DIST_DIR,
                        solr_version: str = MC_SOLR_VERSION,
                        jvm_heap_size: str = MC_SOLR_STANDALONE_JVM_HEAP_SIZE):
    """Run standalone instance of Solr."""
    if hostname is None:
        hostname = fqdn()
    if not __solr_is_installed(dist_directory=dist_directory, solr_version=solr_version):
        log.info("Solr is not installed, installing...")
        __install_solr(dist_directory=dist_directory, solr_version=solr_version)

    base_data_dir = resolve_absolute_path_under_mc_root(path=base_data_dir, must_exist=True)
    standalone_data_dir = __standalone_data_dir(base_data_dir=base_data_dir)

    if tcp_port_is_open(port=port):
        raise McSolrRunException("Port %d is already open on this machine." % port)

    log.info("Starting standalone Solr instance on port %d..." % port)
    __run_solr(hostname=hostname,
               port=port,
               instance_data_dir=standalone_data_dir,
               jvm_heap_size=jvm_heap_size,
               jvm_opts=MC_SOLR_STANDALONE_JVM_OPTS,
               connect_timeout=MC_SOLR_STANDALONE_CONNECT_RETRIES,
               dist_directory=dist_directory,
               solr_version=solr_version)


def run_solr_shard(shard_num: int,
                   shard_count: int,
                   hostname: str = None,
                   starting_port: int = MC_SOLR_CLUSTER_STARTING_PORT,
                   base_data_dir: str = MC_SOLR_BASE_DATA_DIR,
                   dist_directory: str = MC_DIST_DIR,
                   solr_version: str = MC_SOLR_VERSION,
                   zookeeper_host: str = MC_SOLR_CLUSTER_ZOOKEEPER_HOST,
                   zookeeper_port: int = MC_SOLR_CLUSTER_ZOOKEEPER_PORT,
                   jvm_heap_size: str = MC_SOLR_CLUSTER_JVM_HEAP_SIZE) -> None:
    """Run Solr shard, install Solr if needed; read configuration from ZooKeeper."""
    if shard_num < 1:
        raise McSolrRunException("Shard number must be 1 or greater.")
    if shard_count < 1:
        raise McSolrRunException("Shard count must be 1 or greater.")

    if not __solr_is_installed(dist_directory=dist_directory, solr_version=solr_version):
        log.info("Solr is not installed, installing...")
        __install_solr(dist_directory=dist_directory, solr_version=solr_version)

    if hostname is None:
        hostname = fqdn()

    base_data_dir = resolve_absolute_path_under_mc_root(path=base_data_dir, must_exist=True)

    shard_port = __shard_port(shard_num=shard_num, starting_port=starting_port)
    shard_data_dir = __shard_data_dir(shard_num=shard_num, base_data_dir=base_data_dir)

    log.info("Waiting for ZooKeeper to start on %s:%d..." % (zookeeper_host, zookeeper_port))
    wait_for_tcp_port_to_open(hostname=zookeeper_host,
                              port=zookeeper_port,
                              retries=MC_SOLR_CLUSTER_ZOOKEEPER_CONNECT_RETRIES)
    log.info("ZooKeeper is up!")

    log.info("Starting Solr shard %d on port %d..." % (shard_num, shard_port))
    # noinspection SpellCheckingInspection
    shard_args = [
        "-DzkHost=%s:%d" % (zookeeper_host, zookeeper_port),
        "-DnumShards=%d" % shard_count,
    ]
    __run_solr(hostname=hostname,
               port=shard_port,
               instance_data_dir=shard_data_dir,
               jvm_heap_size=jvm_heap_size,
               jvm_opts=MC_SOLR_CLUSTER_JVM_OPTS,
               start_jar_args=shard_args,
               connect_timeout=MC_SOLR_CLUSTER_CONNECT_RETRIES,
               dist_directory=dist_directory,
               solr_version=solr_version)


def reload_solr_shard(shard_num: int,
                      host: str = "localhost",
                      starting_port: int = MC_SOLR_CLUSTER_STARTING_PORT):
    """Reload Solr shard after ZooKeeper configuration change."""
    if shard_num < 1:
        raise McSolrRunException("Shard number must be 1 or greater.")

    shard_port = __shard_port(shard_num=shard_num, starting_port=starting_port)

    if not tcp_port_is_open(hostname=host, port=shard_port):
        raise McSolrRunException("Shard %d is not running on %s:%d." % (shard_num, host, shard_port))

    log.info("Reloading shard %d on %s:%d..." % (shard_num, host, shard_port))

    collections = __collections()
    log.debug("Solr collections: %s" % collections)

    for collection_name, collection_path in sorted(collections.items()):
        log.info("Reloading collection '%s' on shard %d on %s:%d..." % (
            collection_name, shard_num, host, shard_port
        ))
        url = "http://%(host)s:%(port)d/solr/admin/cores?action=RELOAD&core=%(collection_name)s" % {
            "host": host,
            "port": shard_port,
            "collection_name": collection_name,
        }
        log.debug("Requesting URL %s..." % url)

        try:
            urlopen(url)
        except URLError as e:
            raise McSolrRunException("Unable to reload shard %d on %s:%d: %s" % (shard_num, host, shard_port, e.reason))

    log.info("Reloaded shard %d on %s:%d." % (shard_num, host, shard_port))


def reload_all_solr_shards(shard_count: int,
                           host: str = "localhost",
                           starting_port: int = MC_SOLR_CLUSTER_STARTING_PORT) -> None:
    """Reload all Solr shards after ZooKeeper configuration change."""
    if shard_count < 1:
        raise McSolrRunException("Shard count must be 1 or greater.")

    log.info("Reloading %d shards on %s..." % (shard_count, host))
    for shard_num in range(1, shard_count + 1):
        reload_solr_shard(shard_num=shard_num, host=host, starting_port=starting_port)
    log.info("Reloaded %d shards on %s." % (shard_count, host))


def optimize_solr_index(host: str = "localhost",
                        port: int = MC_SOLR_STANDALONE_PORT,
                        collections: List[str] = None):
    """Optimize collection indexes.

    In SolrCloud cluster, optimization command run on one of the shards will trigger optimization on all of them."""

    if collections is None:
        collections = __collections().keys()

    log.debug("Solr collections to reindex: %s" % ', '.join(collections))

    if not tcp_port_is_open(hostname=host, port=port):
        raise McSolrRunException("Solr is not running on %s:%d." % (host, port))

    log.info("Optimizing indexes on %s:%d..." % (host, port))

    for collection_name in sorted(collections):
        log.info("Optimizing collection's '%s' index on %s:%d..." % (
            collection_name, host, port))

        url = "http://%(host)s:%(port)d/solr/%(collection_name)s/update?optimize=true" % {
            "host": host,
            "port": port,
            "collection_name": collection_name,
        }
        log.debug("Requesting URL %s..." % url)

        try:
            urlopen(url)
        except URLError as e:
            raise McSolrRunException("Unable to optimize collection '%s' index on %s:%d: %s" % (
                collection_name, host, port, e.reason))

    log.info("Optimized indexes on %s:%d." % (host, port))


def __upgrade_lucene_index(instance_data_dir: str,
                           dist_directory: str = MC_DIST_DIR,
                           solr_version: str = MC_SOLR_VERSION):
    """Upgrade Solr (Lucene) index using the IndexUpgrader tool in a given instance directory."""
    if not __solr_is_installed(dist_directory=dist_directory, solr_version=solr_version):
        log.info("Solr is not installed, installing...")
        __install_solr(dist_directory=dist_directory, solr_version=solr_version)

    if not os.path.isdir(instance_data_dir):
        raise McSolrRunException("Instance data directory '%s' does not exist." % instance_data_dir)

    solr_path = __solr_path(dist_directory=dist_directory, solr_version=solr_version)

    lucene_lib_path = os.path.join(solr_path, "server", "solr-webapp", "webapp", "WEB-INF", "lib")
    if not os.path.isdir(lucene_lib_path):
        raise McSolrRunException("Lucene library directory '%s' does not exist.")

    lucene_core_jar = glob.glob(lucene_lib_path + "/lucene-core-*.jar")
    if len(lucene_core_jar) != 1:
        raise McSolrRunException("lucene-core JAR was not found in '%s'." % lucene_lib_path)
    lucene_core_jar = lucene_core_jar[0]

    lucene_backward_codecs_jar = glob.glob(lucene_lib_path + "/lucene-backward-codecs-*.jar")
    if len(lucene_backward_codecs_jar) != 1:
        raise McSolrRunException("lucene-backward-codecs JAR was not found in '%s'." % lucene_lib_path)
    lucene_backward_codecs_jar = lucene_backward_codecs_jar[0]

    collections = __collections().keys()
    for collection_name in collections:
        collection_path = os.path.join(instance_data_dir, collection_name)
        if not os.path.isdir(collection_path):
            raise McSolrRunException("Collection data directory '%s' does not exist." % collection_path)
        index_path = os.path.join(collection_path, "data", "index")
        if not os.path.isdir(index_path):
            raise McSolrRunException("Index directory '%s' does not exist." % index_path)

        log.info("Upgrading index at path '%s'..." % index_path)
        args = [
            "java",
            "-cp", ":".join([lucene_core_jar, lucene_backward_codecs_jar]),
            "org.apache.lucene.index.IndexUpgrader",
            "-verbose",
            index_path,
        ]
        run_command_in_foreground(args)
        log.info("Upgraded index at path '%s'." % index_path)


def upgrade_lucene_standalone_index(base_data_dir: str = MC_SOLR_BASE_DATA_DIR,
                                    dist_directory: str = MC_DIST_DIR,
                                    solr_version: str = MC_SOLR_VERSION):
    """Upgrade Lucene index using the IndexUpgrader tool to standalone instance."""

    base_data_dir = resolve_absolute_path_under_mc_root(path=base_data_dir, must_exist=True)

    log.info("Making sure standalone instance isn't running...")
    port = MC_SOLR_STANDALONE_PORT
    if tcp_port_is_open(port=port):
        raise McSolrRunException("Solr standalone instance is running on port %d." % port)
    log.info("Made sure standalone instance isn't running.")

    log.info("Upgrading standalone instance indexes...")
    standalone_data_dir = __standalone_data_dir(base_data_dir=base_data_dir)
    __upgrade_lucene_index(instance_data_dir=standalone_data_dir,
                           dist_directory=dist_directory,
                           solr_version=solr_version)
    log.info("Upgraded standalone instance indexes...")


def upgrade_lucene_shards_indexes(base_data_dir: str = MC_SOLR_BASE_DATA_DIR,
                                  dist_directory: str = MC_DIST_DIR,
                                  solr_version: str = MC_SOLR_VERSION):
    """Upgrade Lucene indexes using the IndexUpgrader tool to all shards."""

    base_data_dir = resolve_absolute_path_under_mc_root(path=base_data_dir, must_exist=True)

    # Try to guess shard count from how many shards are in data directory
    log.info("Looking for shards...")
    shard_num = 0
    shard_count = 0
    while True:
        shard_num += 1
        shard_data_dir = __shard_data_dir(shard_num=shard_num, base_data_dir=base_data_dir)
        if os.path.isdir(shard_data_dir):
            shard_count += 1
        else:
            break
    if shard_count < 2:
        raise McSolrRunException("Found less than 2 shards.")
    log.info("Found %d shards." % shard_count)

    log.info("Making sure shards aren't running...")
    for shard_num in range(1, shard_count + 1):
        shard_port = __shard_port(shard_num=shard_num, starting_port=MC_SOLR_CLUSTER_STARTING_PORT)

        if tcp_port_is_open(port=shard_port):
            raise McSolrRunException("Solr shard %d is running on port %d." % (shard_num, shard_port))
    log.info("Made sure shards aren't running.")

    log.info("Upgrading shard indexes...")
    for shard_num in range(1, shard_count + 1):
        shard_data_dir = __shard_data_dir(shard_num=shard_num, base_data_dir=base_data_dir)
        __upgrade_lucene_index(instance_data_dir=shard_data_dir,
                               dist_directory=dist_directory,
                               solr_version=solr_version)
    log.info("Upgraded shard indexes.")
