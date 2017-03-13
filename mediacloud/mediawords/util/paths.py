import errno
import os
import time

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

l = create_logger(__name__)

__FILE_THAT_EXISTS_AT_ROOT_PATH = 'mediawords.yml.dist'


class McRootPathException(Exception):
    pass


def mc_root_path() -> str:
    """Return full path to Media Cloud root directory."""
    # MC_REWRITE_TO_PYTHON: Inline::Python doesn't always set __file__
    # properly, but chances are that we're running from Media Cloud root directory
    try:
        __file__
    except NameError:
        pwd = os.getcwd()
        l.debug("__file__ is undefined, trying current directory to pass as Media Cloud root: %s" % pwd)
        root_path = pwd
    else:
        root_path = os.path.realpath(os.path.join(__file__, "..", "..", "..", ".."))

    if not os.path.isfile(os.path.join(root_path, __FILE_THAT_EXISTS_AT_ROOT_PATH)):
        raise McRootPathException("Unable to determine Media Cloud root path (tried '%s')" % root_path)
    l.debug("Root path is %s" % root_path)
    return root_path


def mc_sql_schema_path() -> str:
    """Return full path to SQL schema (mediawords.sql)."""
    return os.path.join(mc_root_path(), 'schema', 'mediawords.sql')


def mkdir_p(path: str) -> None:
    """mkdir -p"""

    path = decode_object_from_bytes_if_needed(path)

    l.debug("Creating directory '%s'..." % path)
    try:
        os.makedirs(path)
    except OSError as e:  # Python >2.5
        if e.errno == errno.EEXIST and os.path.isdir(path):
            pass
        else:
            raise
    l.debug("Created directory '%s'." % path)


class McResolveAbsolutePathUnderMcRootException(Exception):
    pass


def resolve_absolute_path_under_mc_root(path: str, must_exist: bool = False) -> str:
    """Return absolute path to object (file or directory) under Media Cloud root."""

    path = decode_object_from_bytes_if_needed(path)

    mc_root = mc_root_path()
    dist_path = os.path.join(mc_root, path)
    if must_exist:
        if not os.path.exists(dist_path):
            raise McResolveAbsolutePathUnderMcRootException(
                "Object '%s' at path '%s' does not exist." % (path, dist_path)
            )
    return os.path.abspath(dist_path)


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

    l.debug("Creating relative symlink from '%s' to '%s'..." % (rel_source, link_name))
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
    l.debug("Creating lock file '%s'..." % path)
    while True:
        try:
            os.open(path, os.O_CREAT | os.O_EXCL | os.O_RDWR)
            break
        except OSError as e:
            if e.errno == errno.EEXIST:
                if timeout is not None:
                    if (time.time() - start_time) >= timeout:
                        raise McLockFileException("Unable to create lock file '%s' in %d seconds." % (path, timeout))

                l.info("Lock file '%s' already exists, will retry shortly." % path)
                time.sleep(1)
            else:
                # Some other I/O error
                raise
    l.debug("Created lock file '%s'" % path)


class McUnlockFileException(Exception):
    pass


def unlock_file(path: str) -> None:
    """Remove lock file."""
    # FIXME probably not thread-safe

    path = decode_object_from_bytes_if_needed(path)

    l.debug("Removing lock file '%s'..." % path)
    if not os.path.isfile(path):
        raise McUnlockFileException("Lock file '%s' does not exist." % path)
    os.unlink(path)
    l.debug("Removed lock file '%s'." % path)
