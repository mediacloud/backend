import os
import subprocess
import tempfile

import pytest

from mediawords.util.process import (
    process_with_pid_is_running,
    run_command_in_foreground,
    gracefully_kill_child_process,
    McRunCommandInForegroundException,
)


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

    test_process.communicate()
    assert process_with_pid_is_running(test_process_pid) is False


def test_run_command_in_foreground():
    temp_dir = tempfile.mkdtemp()

    test_file_to_create = os.path.join(temp_dir, 'test.txt')
    assert os.path.isfile(test_file_to_create) is False

    run_command_in_foreground(['touch', test_file_to_create])
    assert os.path.isfile(test_file_to_create) is True

    run_command_in_foreground(['rm', test_file_to_create])
    assert os.path.isfile(test_file_to_create) is False

    # Environment variables
    test_env_variable = 'MC_RUN_COMMAND_IN_FOREGROUND_ENV_TEST'
    test_file_with_env = os.path.join(temp_dir, 'env.txt')
    test_file_without_env = os.path.join(temp_dir, 'no-env.txt')
    run_command_in_foreground(['/bin/bash', '-c', 'env > %s' % test_file_with_env],
                              env={test_env_variable: '1'})
    run_command_in_foreground(['/bin/bash', '-c', 'env > %s' % test_file_without_env], env={})
    with open(test_file_with_env, 'r') as f:
        contents = f.read()
        assert test_env_variable in contents
    with open(test_file_without_env, 'r') as f:
        contents = f.read()
        assert test_env_variable not in contents

    # cwd
    test_file_with_cwd = os.path.join(temp_dir, 'cwd.txt')
    test_file_without_cwd = os.path.join(temp_dir, 'no-cwd.txt')
    run_command_in_foreground(['/bin/bash', '-c', 'pwd > %s' % test_file_with_cwd], cwd=temp_dir)
    run_command_in_foreground(['/bin/bash', '-c', 'pwd > %s' % test_file_without_cwd])
    with open(test_file_with_cwd, 'r') as f:
        contents = f.read()
        assert temp_dir in contents
    with open(test_file_without_cwd, 'r') as f:
        contents = f.read()
        assert temp_dir not in contents

    # Faulty command
    with pytest.raises(McRunCommandInForegroundException):
        run_command_in_foreground(['this_command_totally_doesnt_exist'])


def test_gracefully_kill_child_process():
    test_process = subprocess.Popen(['sleep', '999'])
    test_process_pid = test_process.pid

    assert test_process_pid != 0
    assert test_process_pid is not None

    assert process_with_pid_is_running(test_process_pid) is True

    gracefully_kill_child_process(child_pid=test_process_pid, sigkill_timeout=3)

    test_process.communicate()
    assert process_with_pid_is_running(test_process_pid) is False
