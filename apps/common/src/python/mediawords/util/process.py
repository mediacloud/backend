import os

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


def fatal_error(message: str) -> None:
    """Print error message, exit(1) the process.

    Sometimes when an error happens, we can't use die() because it would get caught in try-except.

    We don't always want that: for example, if crawler dies because of misconfiguration in mediawords.yml, crawler's
    errors would get logged into "downloads" table as if the error happened because of a valid reason.

    In those cases, we go straight to exit(1) using this helper subroutine."""

    message = decode_object_from_bytes_if_needed(message)

    log.error(message)

    # noinspection PyProtectedMember
    os._exit(1)
