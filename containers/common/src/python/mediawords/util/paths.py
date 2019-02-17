import errno
import os
import time

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


def mkdir_p(path: str) -> None:
    """mkdir -p"""

    path = decode_object_from_bytes_if_needed(path)

    log.debug("Creating directory '%s'..." % path)
    try:
        os.makedirs(path)
    except OSError as e:  # Python >2.5
        if e.errno == errno.EEXIST and os.path.isdir(path):
            pass
        else:
            raise
    log.debug("Created directory '%s'." % path)


class McResolveAbsolutePathUnderMcRootException(Exception):
    pass


class McRelativeSymlinkException(Exception):
    pass


def relative_symlink(source: str, link_name: str) -> None:
    """Create symlink while also converting paths to relative ones by finding common prefix."""

    source = decode_object_from_bytes_if_needed(source)
    link_name = decode_object_from_bytes_if_needed(link_name)

    source = os.path.abspath(source)
    link_name = os.path.abspath(link_name)

    if not os.path.exists(source):
        raise McRelativeSymlinkException("Symlink source does not exist at path: %s" % source)

    rel_source = os.path.relpath(source, os.path.dirname(link_name))

    log.debug("Creating relative symlink from '%s' to '%s'..." % (rel_source, link_name))
    os.symlink(rel_source, link_name)


def file_extension(filename: str) -> str:
    """Return file extension, e.g. ".zip" for "test.zip", or ".gz" for "test.tar.gz"."""

    filename = decode_object_from_bytes_if_needed(filename)

    basename = os.path.basename(filename)
    root, extension = os.path.splitext(basename)
    return extension.lower()


class McLockFileException(Exception):
    pass


def lock_file(path: str, timeout: int = None) -> None:
    """Create lock file."""
    # FIXME probably not thread-safe

    path = decode_object_from_bytes_if_needed(path)

    start_time = time.time()
    log.debug("Creating lock file '%s'..." % path)
    while True:
        try:
            os.open(path, os.O_CREAT | os.O_EXCL | os.O_RDWR)
            break
        except OSError as e:
            if e.errno == errno.EEXIST:
                if timeout is not None:
                    if (time.time() - start_time) >= timeout:
                        raise McLockFileException("Unable to create lock file '%s' in %d seconds." % (path, timeout))

                log.info("Lock file '%s' already exists, will retry shortly." % path)
                time.sleep(1)
            else:
                # Some other I/O error
                raise
    log.debug("Created lock file '%s'" % path)


class McUnlockFileException(Exception):
    pass


def unlock_file(path: str) -> None:
    """Remove lock file."""
    # FIXME probably not thread-safe

    path = decode_object_from_bytes_if_needed(path)

    log.debug("Removing lock file '%s'..." % path)
    if not os.path.isfile(path):
        raise McUnlockFileException("Lock file '%s' does not exist." % path)
    os.unlink(path)
    log.debug("Removed lock file '%s'." % path)
