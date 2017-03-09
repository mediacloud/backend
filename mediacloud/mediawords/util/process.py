import os
import signal
import sys
import subprocess
import time
from typing import List

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

l = create_logger(__name__)


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


def run_command_in_foreground(command: List[str]) -> None:
    """Run command in foreground, raise McRunCommandInForegroundException if it fails."""
    l.debug("Running command: %s" % ' '.join(command))

    command = decode_object_from_bytes_if_needed(command)

    # Add some more PATHs to look into
    env_path = os.environ.copy()
    env_path['PATH'] = '/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:' + env_path['PATH']

    # noinspection PyBroadException
    try:
        if sys.platform.lower() == 'darwin':
            # OS X -- requires some crazy STDOUT / STDERR buffering
            line_buffered = 1
            process = subprocess.Popen(command,
                                       stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT,
                                       bufsize=line_buffered,
                                       env=env_path)
            while True:
                output = process.stdout.readline()
                if len(output) == 0 and process.poll() is not None:
                    break
                l.info(output.strip())
            rc = process.poll()
            if rc > 0:
                raise McRunCommandInForegroundException("Process returned non-zero exit code %d" % rc)
        else:
            # assume Ubuntu
            subprocess.check_call(command, env=env_path)
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
        l.warning("Child process with PID %d is not running, maybe it's dead already?" % child_pid)
    else:
        l.info("Sending SIGKILL to child process with PID %d..." % child_pid)

        try:
            os.kill(child_pid, signal.SIGKILL)
        except OSError as e:
            # Might be already killed
            l.warning("Unable to send SIGKILL to child PID %d: %s" % (child_pid, str(e)))

        for retry in range(sigkill_timeout):
            if process_with_pid_is_running(pid=child_pid):
                l.info("Child with PID %d is still up (retry %d)." % (child_pid, retry))
                time.sleep(1)
            else:
                break

        if process_with_pid_is_running(pid=child_pid):
            l.warning("SIGKILL didn't work child process with PID %d, sending SIGTERM..." % child_pid)

            try:
                os.kill(child_pid, signal.SIGTERM)
            except OSError as e:
                # Might be already killed
                l.warning("Unable to send SIGTERM to child PID %d: %s" % (child_pid, str(e)))

            time.sleep(3)

        if process_with_pid_is_running(pid=child_pid):
            l.warning("Even SIGKILL didn't do anything, kill child process with PID %d manually!" % child_pid)
