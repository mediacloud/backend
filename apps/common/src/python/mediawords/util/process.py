import os

import psutil

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


def _kill_children(pid: int) -> None:
    """Kill all children of PID except for ourselves."""

    proc = psutil.Process(pid)
    command = proc.cmdline()

    # Kill the children first (except for ourselves) and then go for the parent
    # Go straight for SIGKILL as "acks_late" is set so unfinished jobs should get restarted properly

    # Get the list first because it might change while we're killing processes
    children = list(proc.children(recursive=True))
    log.debug(f"Process children: {children}")
    for child in children:
        # Don't kill ourselves just yet
        if child.pid != os.getpid():
            try:
                log.warning(f"Killing child with PID {child.pid} ({str(child.cmdline())})")
                child.kill()
            except psutil.NoSuchProcess:
                log.warning(f"Child {child.pid} is gone already")

    if pid != os.getpid():
        log.warning(f"Killing parent with PID {proc.pid} ({str(command)})")
        proc.kill()


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
    parent_proc = psutil.Process(os.getppid())
    parent_command = parent_proc.cmdline()

    log.debug(f"Parent command: {parent_command}")

    if 'python3' in parent_command[0].lower() or 'perl' in parent_command[0].lower():
        _kill_children(parent_proc.pid)

    current_proc = psutil.Process(os.getpid())
    current_command = current_proc.cmdline()

    log.debug(f"Current command: {current_command}")

    if 'python3' in current_command[0].lower() or 'perl' in current_command[0].lower():
        _kill_children(current_proc.pid)

    log.warning(f"Killing ourselves with PID {os.getpid()}")

    # noinspection PyProtectedMember
    os._exit(1)
