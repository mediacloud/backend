import logging

import errno
import os
import re
import tempfile

import socket
import subprocess

import time

import signal

import sys


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
    hostname = subprocess.check_output(['hostname', '-f']).strip()  # socket.getfqdn() returns goofy results
    if hostname is None or len(hostname) == 0:
        raise Exception("Unable to determine FQDN.")
    hostname = hostname.lower()
    if hostname == 'localhost':
        logger.warn("FQDN is 'localhost', are you sure that /etc/hosts is set up properly?")
    if not hostname_resolves(hostname):
        raise Exception("Hostname '%s' does not resolve." % hostname)
    return hostname


def hostname_resolves(hostname):
    """Return true if hostname resolves to IP."""
    try:
        socket.gethostbyname(hostname)
        return True
    except socket.error:
        return False


def process_with_pid_is_running(pid):
    """Return true if process with PID is still running."""
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    else:
        return True


def relative_symlink(source, link_name):
    """Create symlink while also converting paths to relative ones by finding common prefix."""
    source = os.path.abspath(source)
    link_name = os.path.abspath(link_name)

    if not os.path.exists(source):
        raise Exception("Symlink source does not exist at path: %s" % source)

    rel_source = os.path.relpath(source, os.path.dirname(link_name))

    logger.debug("Creating relative symlink from '%s' to '%s'..." % (rel_source, link_name))
    os.symlink(rel_source, link_name)


def gracefully_kill_child_process(child_pid, sigkill_timeout=60):
    """Try to kill child process gracefully with SIGKILL, then abruptly with SIGTERM."""
    if child_pid is None:
        raise Exception("Child PID is unset.")

    if not process_with_pid_is_running(pid=child_pid):
        logger.warn("Child process with PID %d is not running, maybe it's dead already?" % child_pid)
    else:
        logger.info("Sending SIGKILL to child process with PID %d..." % child_pid)

        try:
            os.kill(child_pid, signal.SIGKILL)
        except OSError as e:
            # Might be already killed
            logger.warn("Unable to send SIGKILL to child PID %d: %s" % (child_pid, e.message))

        for retry in range(sigkill_timeout):
            if process_with_pid_is_running(pid=child_pid):
                logger.info("Child with PID %d is still up (retry %d)." % (child_pid, retry))
                time.sleep(1)
            else:
                break

        if process_with_pid_is_running(pid=child_pid):
            logger.warn("SIGKILL didn't work child process with PID %d, sending SIGTERM..." % child_pid)

            try:
                os.kill(child_pid, signal.SIGTERM)
            except OSError as e:
                # Might be already killed
                logger.warn("Unable to send SIGTERM to child PID %d: %s" % (child_pid, e.message))

            time.sleep(3)

        if process_with_pid_is_running(pid=child_pid):
            logger.warn("Even SIGKILL didn't do anything, kill child process with PID %d manually!" % child_pid)


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


def run_command_in_foreground(command):
    """Run command in foreground, raise exception if it fails."""
    logger.debug("Running command: %s" % ' '.join(command))

    if sys.platform.lower() == 'darwin':
        # OS X -- requires some crazy STDOUT / STDERR buffering
        line_buffered = 1
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=line_buffered)
        while True:
            output = process.stdout.readline()
            if len(output) == 0 and process.poll() is not None:
                break
            logger.info(output.strip())
        rc = process.poll()
        if rc > 0:
            raise Exception("Process returned non-zero exit code %d" % rc)
    else:
        # assume Ubuntu
        subprocess.check_call(command)


def compare_versions(version1, version2):
    """Compare two version strings. Return 0 if equal, -1 if version1 < version2, 1 if version1 > version2."""

    def normalize(v):
        v = v.replace("_", ".")
        return [int(x) for x in re.sub(r'(\.0+)*$', '', v).split(".")]

    return cmp(normalize(version1), normalize(version2))


def java_version():
    """Return Java version, e.g. "1.8.0_66"."""
    java_version_output = subprocess.Popen(["java", "-version"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    java_version_output = java_version_output.stdout.read()

    java_version_string = re.search(r'(java|openjdk) version "(.+?)"', java_version_output)
    if java_version_string is None:
        raise Exception("Unable to determine Java version from string: %s" % java_version_output)
    java_version_string = java_version_string.group(2)

    return java_version_string
