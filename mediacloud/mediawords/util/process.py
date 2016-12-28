import os


def process_with_pid_is_running(pid: int) -> bool:
    """Return True if process with PID is running."""
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    else:
        return True
