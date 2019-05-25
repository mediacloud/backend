import errno
import os

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
