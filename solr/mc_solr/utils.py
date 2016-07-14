import logging

import errno
import os
import tempfile

import socket
import subprocess

import time


def create_logger(name):
    """Create and return 'logging' instance."""
    formatter = logging.Formatter(fmt='%(asctime)s - %(levelname)s - %(module)s - %(message)s')

    handler = logging.StreamHandler()
    handler.setFormatter(formatter)

    l = logging.getLogger(name)
    l.setLevel(logging.DEBUG)
    l.addHandler(handler)
    return l


logger = create_logger(__name__)


def mkdir_p(path):
    """mkdir -p"""
    logger.debug("Creating directory '%s'..." % path)
    try:
        os.makedirs(path)
    except OSError as e:  # Python >2.5
        if e.errno == errno.EEXIST and os.path.isdir(path):
            pass
        else:
            raise
    logger.debug("Created directory '%s'." % path)


def lock_file(path, timeout=None):
    """Create lock file."""
    start_time = time.time()
    logger.debug("Creating lock file '%s'..." % path)
    while True:
        try:
            os.open(path, os.O_CREAT | os.O_EXCL | os.O_RDWR)
            break
        except OSError as e:
            if e.errno == errno.EEXIST:
                if timeout is not None:
                    if (time.time() - start_time) >= timeout:
                        raise Exception("Unable to create lock file '%s' in %d seconds." % (path, timeout))

                logger.info("Lock file '%s' already exists, will retry shortly." % path)
                time.sleep(1)
            else:
                # Some other I/O error
                raise
    logger.debug("Created lock file '%s'" % path)


def unlock_file(path):
    """Remove lock file."""
    logger.debug("Removing lock file '%s'..." % path)
    if not os.path.isfile(path):
        raise Exception("Lock file '%s' does not exist." % path)
    os.unlink(path)
    logger.debug("Removed lock file '%s'." % path)


def download_file(source_url, target_path):
    """Download URL to path."""
    subprocess.check_call(["curl",
                           "--retry", "3",
                           "--retry-delay", "5",
                           "--output", target_path,
                           source_url])


def download_file_to_temp_path(source_url):
    """Download URL to temporary path."""
    dest_dir = tempfile.mkdtemp()
    dest_path = os.path.join(dest_dir, 'archive.tgz')
    download_file(source_url=source_url, target_path=dest_path)
    return dest_path


def __file_extension(filename):
    """Return file extension, e.g. "zip"."""
    return os.path.splitext(os.path.basename(filename))[1].lower()


def extract_tarball_to_directory(archive_file, dest_directory, strip_root=False):
    """Extract Tar archive (.tar, .tar.gz or .tgz) to destination directory,
    optionally stripping the root directory first."""

    archive_file_extension = __file_extension(archive_file)
    if archive_file_extension in [".tar.gz", ".tgz"]:
        tar_args = "-zxf"
    elif archive_file_extension in [".tar"]:
        tar_args = "-xf"
    else:
        raise Exception("Unsupported archive '%s' with extension '%s'" % (archive_file, archive_file_extension))

    args = ["tar",
            tar_args, archive_file,
            "-C", dest_directory]
    if strip_root:
        args.extend(("--strip", "1"))

    subprocess.check_call(args)


def extract_zip_to_directory(archive_file, dest_directory):
    """Extract ZIP archive (.zip or .war) to destination directory."""

    archive_file_extension = __file_extension(archive_file)
    if not archive_file_extension in [".zip", ".war"]:
        raise Exception("Unsupported archive '%s' with extension '%s'" % (archive_file, archive_file_extension))

    args = ["unzip", "-q",
            archive_file,
            "-d", dest_directory]

    subprocess.check_call(args)


def tcp_port_is_open(port, hostname="localhost"):
    """Test if TCP port is open."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    result = sock.connect_ex((hostname, port))
    return result == 0


def wait_for_tcp_port_to_open(port, hostname="localhost", retries=60, delay=1):
    """Try connecting to TCP port until it opens (or not); return True if managed to connect."""
    port_is_open = False
    for retry in range(retries):
        if retry == 0:
            logger.info("Trying to connect to %s:%d" % (hostname, port))
        else:
            logger.info("Trying to connect to %s:%d, retry %d" % (hostname, port, retry))

        if tcp_port_is_open(port, hostname):
            port_is_open = True
            break
        else:
            time.sleep(delay)
    return port_is_open


def resolve_absolute_path(name, must_exist=False):
    """Return absolute path to object (file or directory) under solr/."""
    script_path = os.path.dirname(os.path.abspath(__file__))
    dist_path = os.path.join(script_path, "..", name)
    if must_exist:
        if not os.path.isdir(dist_path):
            raise Exception("Object '%s' at path '%s' does not exist." % (name, resolve_absolute_path))
    return os.path.abspath(dist_path)