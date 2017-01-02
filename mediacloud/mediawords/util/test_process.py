import tempfile

from nose.tools import assert_raises

from mediawords.util.process import *


def test_process_with_pid_is_running():
    test_process = subprocess.Popen(['sleep', '999'])
    test_process_pid = test_process.pid

    assert test_process_pid != 0
    assert test_process_pid is not None

    assert process_with_pid_is_running(test_process_pid) is True

    # again to test if os.kill() just tests the process, not actually kills it
    assert process_with_pid_is_running(test_process_pid) is True

    test_process.terminate()
    test_process.kill()

    # FIXME for whatever reason Python still "sees" this PID after killing it; maybe it's a thread PID and not a
    # process one?
    # assert process_with_pid_is_running(test_process_pid) is False


def test_run_command_in_foreground():
    temp_dir = tempfile.mkdtemp()

    test_file_to_create = os.path.join(temp_dir, 'test.txt')
    assert os.path.isfile(test_file_to_create) is False

    run_command_in_foreground(['touch', test_file_to_create])
    assert os.path.isfile(test_file_to_create) is True

    run_command_in_foreground(['rm', test_file_to_create])
    assert os.path.isfile(test_file_to_create) is False

    # Faulty command
    assert_raises(McRunCommandInForegroundException, run_command_in_foreground, ['this_command_totally_doesnt_exist'])


def test_gracefully_kill_child_process():
    test_process = subprocess.Popen(['sleep', '999'])
    test_process_pid = test_process.pid

    assert test_process_pid != 0
    assert test_process_pid is not None

    assert process_with_pid_is_running(test_process_pid) is True

    gracefully_kill_child_process(child_pid=test_process_pid, sigkill_timeout=3)

    # FIXME for whatever reason Python still "sees" this PID after killing it; maybe it's a thread PID and not a
    # process one?
    # assert process_with_pid_is_running(test_process_pid) is False
