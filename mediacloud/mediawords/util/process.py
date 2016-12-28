import os
import sys
import subprocess
from typing import List

from mediawords.util.log import create_logger

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

    # noinspection PyBroadException
    try:
        if sys.platform.lower() == 'darwin':
            # OS X -- requires some crazy STDOUT / STDERR buffering
            line_buffered = 1
            process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=line_buffered)
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
            subprocess.check_call(command)
    except subprocess.CalledProcessError as ex:
        raise McRunCommandInForegroundException("Process returned non-zero exit code %d" % ex.returncode)
    except Exception as ex:
        raise McRunCommandInForegroundException("Error while running command: %s" % str(ex))
