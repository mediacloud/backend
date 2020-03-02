import os
import signal

import psutil

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

    # If a Celery worker calls fatal_error(), it doesn't manage to kill the parent process because Celery forks new
    # processes to run the actual job. So, find the parent process and send it a signal too for it to shut down.
    parent_pid = os.getppid()
    for proc in psutil.process_iter():
        if proc.pid == parent_pid:
            parent_command = proc.cmdline()
            if 'python3' in parent_command[0].lower():
                parent_group_id = os.getpgid(parent_pid)

                log.warning(f"Killing parent PID {parent_pid}, group {parent_group_id} ({str(parent_command)}) too")

                # Kill the whole group; also, go straight for SIGKILL as "acks_late" is set so unfinished jobs should
                # get restarted properly
                os.killpg(parent_group_id, signal.SIGKILL)

    # noinspection PyProtectedMember
    os._exit(1)
