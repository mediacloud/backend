import errno
import os
import re
import socket
import subprocess
import tempfile
import time

from mediawords.util.network import hostname_resolves

from mediawords.util.paths import mc_root_path
from mediawords.util.log import create_logger
from mediawords.util.process import run_command_in_foreground

l = create_logger(__name__)


def lock_file(path, timeout=None):
    """Create lock file."""
    start_time = time.time()
    l.debug("Creating lock file '%s'..." % path)
    while True:
        try:
            os.open(path, os.O_CREAT | os.O_EXCL | os.O_RDWR)
            break
        except OSError as e:
            if e.errno == errno.EEXIST:
                if timeout is not None:
                    if (time.time() - start_time) >= timeout:
                        raise Exception("Unable to create lock file '%s' in %d seconds." % (path, timeout))

                l.info("Lock file '%s' already exists, will retry shortly." % path)
                time.sleep(1)
            else:
                # Some other I/O error
                raise
    l.debug("Created lock file '%s'" % path)


def unlock_file(path):
    """Remove lock file."""
    l.debug("Removing lock file '%s'..." % path)
    if not os.path.isfile(path):
        raise Exception("Lock file '%s' does not exist." % path)
    os.unlink(path)
    l.debug("Removed lock file '%s'." % path)


def download_file(source_url, target_path):
    """Download URL to path."""
    args = ["curl",
            "--silent",
            "--show-error",
            "--retry", "3",
            "--retry-delay", "5",
            "--output", target_path,
            source_url]
    run_command_in_foreground(args)


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

    run_command_in_foreground(args)


def extract_zip_to_directory(archive_file, dest_directory):
    """Extract ZIP archive (.zip or .war) to destination directory."""

    archive_file_extension = __file_extension(archive_file)
    if archive_file_extension not in [".zip", ".war"]:
        raise Exception("Unsupported archive '%s' with extension '%s'" % (archive_file, archive_file_extension))

    args = ["unzip", "-q",
            archive_file,
            "-d", dest_directory]

    run_command_in_foreground(args)


def fqdn():
    """Return Fully Qualified Domain Name (hostname -f), e.g. mcquery2.media.mit.edu."""
    # socket.getfqdn() returns goofy results
    hostname = socket.getaddrinfo(socket.gethostname(), 0, flags=socket.AI_CANONNAME)[0][3]
    if hostname is None or len(hostname) == 0:
        raise Exception("Unable to determine FQDN.")
    hostname = hostname.lower()
    if hostname == 'localhost':
        l.warning("FQDN is 'localhost', are you sure that /etc/hosts is set up properly?")
    if not hostname_resolves(hostname):
        raise Exception("Hostname '%s' does not resolve." % hostname)
    return hostname


def relative_symlink(source, link_name):
    """Create symlink while also converting paths to relative ones by finding common prefix."""
    source = os.path.abspath(source)
    link_name = os.path.abspath(link_name)

    if not os.path.exists(source):
        raise Exception("Symlink source does not exist at path: %s" % source)

    rel_source = os.path.relpath(source, os.path.dirname(link_name))

    l.debug("Creating relative symlink from '%s' to '%s'..." % (rel_source, link_name))
    os.symlink(rel_source, link_name)


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
            l.info("Trying to connect to %s:%d" % (hostname, port))
        else:
            l.info("Trying to connect to %s:%d, retry %d" % (hostname, port, retry))

        if tcp_port_is_open(port, hostname):
            port_is_open = True
            break
        else:
            time.sleep(delay)
    return port_is_open


def resolve_absolute_path_under_mc_root(name, must_exist=False):
    """Return absolute path to object (file or directory) under Media Cloud root."""
    mc_root = mc_root_path()
    dist_path = os.path.join(mc_root, name)
    if must_exist:
        if not os.path.isdir(dist_path):
            raise Exception("Object '%s' at path '%s' does not exist." % (name, dist_path))
    return os.path.abspath(dist_path)


def compare_versions(version1, version2):
    """Compare two version strings. Return 0 if equal, -1 if version1 < version2, 1 if version1 > version2."""

    def __cmp(a, b):
        # Python 3 does not have cmp()
        return (a > b) - (a < b)

    def __normalize(v):
        v = v.replace("_", ".")
        return [int(x) for x in re.sub(r'(\.0+)*$', '', v).split(".")]

    return __cmp(__normalize(version1), __normalize(version2))


def java_version():
    """Return Java version, e.g. "1.8.0_66"."""
    java_version_output = subprocess.Popen(["java", "-version"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    java_version_output = java_version_output.stdout.read().decode('utf-8')

    java_version_string = re.search(r'(java|openjdk) version "(.+?)"', java_version_output)
    if java_version_string is None:
        raise Exception("Unable to determine Java version from string: %s" % java_version_output)
    java_version_string = java_version_string.group(2)

    return java_version_string
