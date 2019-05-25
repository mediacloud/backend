import os
import signal
import sys
import subprocess
import time
from typing import List, Dict, Union

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


def process_with_pid_is_running(pid: int) -> bool:
    """Return True if process with PID is running."""
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    else:
        return True


class McRunCommandInForegroundException(subprocess.SubprocessError):
    pass


def run_command_in_foreground(command: List[str], env: Union[Dict[str, str], None] = None, cwd: str = None) -> None:
    """Run command in foreground, raise McRunCommandInForegroundException if it fails."""
    log.debug("Running command: %s" % ' '.join(command))

    if len(command) == 0:
        raise McRunCommandInForegroundException('Command is empty.')

    command = decode_object_from_bytes_if_needed(command)

    # Add some more PATHs to look into
    process_env = os.environ.copy()
    process_env['PATH'] = '/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:' + process_env['PATH']

    if env is not None:
        process_env.update(env)

    # noinspection PyBroadException
    try:
        if sys.platform.lower() == 'darwin':
            # OS X -- requires some crazy STDOUT / STDERR buffering
            line_buffered = 1
            process = subprocess.Popen(command,
                                       stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT,
                                       bufsize=line_buffered,
                                       env=process_env,
                                       cwd=cwd)
            while True:
                output = process.stdout.readline()
                if len(output) == 0 and process.poll() is not None:
                    break
                log.info(output.strip())
            rc = process.poll()
            if rc > 0:
                raise McRunCommandInForegroundException("Process returned non-zero exit code %d" % rc)
        else:
            # assume Ubuntu
            subprocess.check_call(command, env=process_env, cwd=cwd)
    except subprocess.CalledProcessError as ex:
        raise McRunCommandInForegroundException("Process returned non-zero exit code %d" % ex.returncode)
    except Exception as ex:
        raise McRunCommandInForegroundException("Error while running command: %s" % str(ex))


class McGracefullyKillChildProcessException(Exception):
    pass


def gracefully_kill_child_process(child_pid: int, sigkill_timeout: int = 60) -> None:
    """Try to kill child process gracefully with SIGKILL, then abruptly with SIGTERM."""
    if child_pid is None:
        raise McGracefullyKillChildProcessException("Child PID is unset.")

    if not process_with_pid_is_running(pid=child_pid):
        log.warning("Child process with PID %d is not running, maybe it's dead already?" % child_pid)
    else:
        log.info("Sending SIGKILL to child process with PID %d..." % child_pid)

        try:
            os.kill(child_pid, signal.SIGKILL)
        except OSError as e:
            # Might be already killed
            log.warning("Unable to send SIGKILL to child PID %d: %s" % (child_pid, str(e)))

        for retry in range(sigkill_timeout):
            if process_with_pid_is_running(pid=child_pid):
                log.info("Child with PID %d is still up (retry %d)." % (child_pid, retry))
                time.sleep(1)
            else:
                break

        if process_with_pid_is_running(pid=child_pid):
            log.warning("SIGKILL didn't work child process with PID %d, sending SIGTERM..." % child_pid)

            try:
                os.kill(child_pid, signal.SIGTERM)
            except OSError as e:
                # Might be already killed
                log.warning("Unable to send SIGTERM to child PID %d: %s" % (child_pid, str(e)))

            time.sleep(3)

        if process_with_pid_is_running(pid=child_pid):
            log.warning("Even SIGKILL didn't do anything, kill child process with PID %d manually!" % child_pid)


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
