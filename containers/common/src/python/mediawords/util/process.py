import atexit
import hashlib
import inspect
import os
import signal
import sys
import subprocess
import time
from typing import List, Callable, Any, Dict, Union

from mediawords.util.log import create_logger
from mediawords.util.paths import lock_file, McLockFileException, unlock_file, McUnlockFileException
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


class McRunAloneException(Exception):
    """Exception on run_alone()."""
    pass


class McUnableToDetermineCaller(McRunAloneException):
    """Exception thrown when run_alone() can not determine caller."""
    pass


class McScriptInstanceIsAlreadyRunning(McRunAloneException):
    """Exception thrown when another instance of the caller script is already running."""
    pass


__run_alone_function_lock_file = None


def __function_unique_id(func: Callable) -> str:
    """Return unique signature of the function, consisting of its absolute path and a name.

    Retry locking for 5 seconds before giving up."""

    function_module = inspect.getmodule(func)
    function_signature = inspect.signature(func)

    module_path = function_module.__file__
    if not os.path.isfile(module_path):
        raise Exception("Module '%s' for function '%s' does not exist." % (module_path, str(func)))

    function_name = func.__qualname__
    if function_name is None or len(function_name) == 0:
        raise Exception("Unable to determine function name: %s" % str(func))

    parameters_type = str(function_signature.parameters)
    return_value_type = str(function_signature.return_annotation)

    unique_id = '%(module_path)s:%(function_name)s:%(parameters)s:%(return_value)s' % {
        'module_path': module_path,
        'function_name': function_name,
        'parameters': parameters_type,
        'return_value': return_value_type,
    }
    return unique_id


# noinspection PyUnusedLocal
def __remove_run_alone_lock_file(signum: int = None,
                                 frame: int = None,
                                 no_exception: bool = False) -> None:
    global __run_alone_function_lock_file

    if __run_alone_function_lock_file is not None:
        log.info("Caught SIGTERM, unlocking '%s'..." % __run_alone_function_lock_file)
        try:
            unlock_file(__run_alone_function_lock_file)
        except McUnlockFileException as exception:
            # Not critical, the lock file might have been removed by some other process
            log.warning("Unlocking file failed: %s" % str(exception))
    else:
        log.debug("Nothing to unlock.")

    if no_exception:
        # noinspection PyProtectedMember
        os._exit(signum)
    else:
        sys.exit(signum)


def run_alone(isolated_function: Callable, *args, **kwargs) -> Any:
    """Run function while making sure that only a single instance of it is running."""

    global __run_alone_function_lock_file

    try:
        function_unique_id = __function_unique_id(isolated_function)
    except Exception as ex:
        raise McUnableToDetermineCaller("Unable to determine caller script: %s" % str(ex))

    timeout = 5

    log.debug("Function unique ID: %s" % function_unique_id)

    function_unique_id_hash = hashlib.sha256(bytes(function_unique_id, 'utf-8')).hexdigest()
    log.debug("Function unique ID hash: %s" % function_unique_id_hash)

    # Catch SIGINTs and SIGTERMs while running the function to be able to remove lock file afterwards
    original_sigint_handler = signal.getsignal(signal.SIGINT)
    original_sigterm_handler = signal.getsignal(signal.SIGTERM)
    signal.signal(signal.SIGINT, __remove_run_alone_lock_file)
    signal.signal(signal.SIGTERM, __remove_run_alone_lock_file)
    atexit.register(__remove_run_alone_lock_file, signum=0, no_exception=True)

    try:

        if sys.platform.lower() == 'darwin':
            # OS X -- /var/run is not world-writable by default
            lock_file_path = '/var/tmp'
        else:
            # Linux -- keep lock files in '/var/run/lock' as they will be removed after reboot
            lock_file_path = '/var/run/lock'

        if not os.path.exists(lock_file_path):
            raise McRunAloneException(
                'Lock file location "%s" does not exist.' % lock_file_path
            )
        if not os.access(lock_file_path, os.W_OK):
            raise McRunAloneException(
                'Lock file location "%s" exists but is not writable.' % lock_file_path
            )

        function_lock_file = os.path.join(lock_file_path, function_unique_id_hash)

        try:
            lock_file(path=function_lock_file, timeout=timeout)
            __run_alone_function_lock_file = function_lock_file
        except McLockFileException as ex:
            raise McScriptInstanceIsAlreadyRunning(
                "Instance of %s is already running: %s" % (str(isolated_function), str(ex))
            )

        # noinspection PyCallingNonCallable
        return_value = isolated_function(*args, **kwargs)

        try:
            unlock_file(__run_alone_function_lock_file)
        except McUnlockFileException as exc:
            # Not critical, the lock file might have been removed by some other process
            log.warning("Unlocking file failed: %s" % str(exc))

    except Exception as ex:

        raise ex

    # We want to reset signal handlers no matter what because if they remain set, weird things happen (e.g. pytest
    # doesn't exit(1) on failures)
    finally:

        atexit.unregister(__remove_run_alone_lock_file)
        signal.signal(signal.SIGINT, original_sigint_handler)
        signal.signal(signal.SIGTERM, original_sigterm_handler)

        __run_alone_function_lock_file = None

    return return_value


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
