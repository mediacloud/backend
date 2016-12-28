import subprocess

from mediawords.util.process import *


def test_process_with_pid_is_running():
    test_process = subprocess.Popen(['sleep', '999'])
    test_process_pid = test_process.pid

    assert test_process_pid != 0
    assert test_process_pid is not None

    assert process_with_pid_is_running(test_process_pid) is True

    # again to test if os.kill() just tests the process, not actually kills it
    assert process_with_pid_is_running(test_process_pid) is True

    test_process.kill()

    assert process_with_pid_is_running(test_process_pid) is False
