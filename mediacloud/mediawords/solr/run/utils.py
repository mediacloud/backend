import errno
import os
import time

from mediawords.util.log import create_logger

l = create_logger(__name__)


def lock_file(path: str, timeout: int = None) -> None:
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


def unlock_file(path: str) -> None:
    """Remove lock file."""
    l.debug("Removing lock file '%s'..." % path)
    if not os.path.isfile(path):
        raise Exception("Lock file '%s' does not exist." % path)
    os.unlink(path)
    l.debug("Removed lock file '%s'." % path)
