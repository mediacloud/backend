import base64
import os
import secrets

import pytest

from mediawords.util.config import env_value, McConfigEnvironmentVariableUnsetException, file_with_env_value
from mediawords.util.text import random_string


def test_env_value():
    random_env_name = random_string(length=16)
    random_env_value = random_string(length=16)

    os.environ[random_env_name] = random_env_value

    assert env_value(name=random_env_name) == random_env_value


def test_env_value_required():
    nonexistent_env_name = random_string(length=16)

    with pytest.raises(McConfigEnvironmentVariableUnsetException):
        env_value(name=nonexistent_env_name)

    assert env_value(name=nonexistent_env_name, required=False) is None


def test_env_value_empty_string():
    empty_env_name = random_string(length=16)

    os.environ[empty_env_name] = ''

    with pytest.raises(McConfigEnvironmentVariableUnsetException):
        env_value(name=empty_env_name)

    assert env_value(name=empty_env_name, allow_empty_string=True) == ''


def test_file_with_env_value():
    random_env_name = random_string(length=16)
    random_env_value = random_string(length=16)

    os.environ[random_env_name] = random_env_value

    env_file = file_with_env_value(name=random_env_name)
    assert os.path.exists(env_file)

    with open(env_file, mode='r') as f:
        assert random_env_value == f.read()

    env_file_2 = file_with_env_value(name=random_env_name)
    assert env_file == env_file_2, f"Helper doesn't recreate file on identical value."

    random_env_value = random_string(length=16)

    # Try changing value
    os.environ[random_env_name] = random_env_value

    env_file_3 = file_with_env_value(name=random_env_name)

    with open(env_file_3, mode='r') as f:
        assert random_env_value == f.read()

    assert env_file != env_file_3, f"Helper recreates file on different value."


def test_file_with_env_value_base64():
    random_env_name = random_string(length=16)
    random_env_value = secrets.token_bytes(16)
    random_env_value_b64 = base64.b64encode(random_env_value).decode('utf-8')

    os.environ[random_env_name] = random_env_value_b64

    env_file = file_with_env_value(name=random_env_name, encoded_with_base64=True)
    assert os.path.exists(env_file)

    with open(env_file, mode='rb') as f:
        assert random_env_value == f.read()
