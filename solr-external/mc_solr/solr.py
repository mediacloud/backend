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


def solr_is_installed(dist_directory=MC_DIST_DIR, solr_version=MC_SOLR_VERSION):
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


def install_solr(dist_directory=MC_DIST_DIR, solr_version=MC_SOLR_VERSION):
    """Install Solr to distribution directory; lock directory before installing and unlock afterwards."""
    if solr_is_installed(dist_directory=dist_directory, solr_version=solr_version):
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
    if solr_is_installed(dist_directory=dist_directory, solr_version=solr_version):
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

    if not solr_is_installed(dist_directory=dist_directory, solr_version=solr_version):
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


def solr_collections(solr_home_dir=MC_SOLR_HOME_DIR):
    """Return dictionary with names and absolute paths to Solr collections."""
    collections = {}
    collections_path = __solr_collections_path(solr_home_dir)
    collection_names = os.listdir(collections_path)
    logger.debug("Collection names: %s" % collection_names)
    for name in collection_names:
        if not name.startswith("_"):
            full_path = os.path.join(collections_path, name)
            if os.path.isdir(full_path):

                collection_conf_path = os.path.join(full_path, "conf")
                if not os.path.isdir(collection_conf_path):
                    raise Exception("Collection configuration path for collection '%s' does not exist." % name)

                collections[name] = full_path

    return collections


def run_solr_zkcli(args, dist_directory=MC_DIST_DIR, solr_version=MC_SOLR_VERSION):
    """Run Solr's zkcli.sh helper script."""
    solr_path = __solr_path(dist_directory=dist_directory, solr_version=solr_version)

    # Solr 4
    log4j_properties_path = os.path.join(solr_path, "example", "cloud-scripts", "log4j.properties")
    if not os.path.isfile(log4j_properties_path):
        log4j_properties_path = os.path.join(solr_path, "server", "scripts", "cloud-scripts", "log4j.properties")
        if not os.path.isfile(log4j_properties_path):
            raise Exception("Unable to find log4j.properties file for zkcli.sh script")

    java_classpath_dirs = [
        # Solr 4
        os.path.join(solr_path, "dist", "*"),
        os.path.join(solr_path, "example", "solr-webapp", "webapp", "WEB-INF", "lib", "*"),
        os.path.join(solr_path, "example", "lib", "ext", "*"),
    ]
    subprocess.check_call(["java",
                           "-classpath", ":".join(java_classpath_dirs),
                           "-Dlog4j.configuration=file://" + os.path.abspath(log4j_properties_path),
                           "org.apache.solr.cloud.ZkCLI"] + args)


def run_solr():
    """Run Solr shard, install if needed too."""
    if not solr_is_installed():
        logger.info("Solr is not installed, installing...")
        install_solr()

        # FIXME
