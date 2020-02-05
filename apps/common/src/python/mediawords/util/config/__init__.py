import base64
import hashlib
import os
import tempfile
from typing import Optional


class McConfigException(Exception):
    """Configuration exception."""
    pass


class McConfigEnvironmentVariableUnsetException(McConfigException):
    """Exception that is raised when an environment variable is unset."""
    pass


def env_value(name: str, required: bool = True, allow_empty_string: bool = False) -> Optional[str]:
    """
    Return value of an environment variable, raise if it's required.

    There can be four types of configuration properties:

    * required and must be a non-empty string;
    * required but can be an empty string;
    * optional and must be a non-empty string (if set);
    * optional but can be an empty string (if set).

    :param name: Environment variable name.
    :param required: If True, will raise if environment variable is not set.
    :param allow_empty_string: If False, will raise if environment variable is set to an empty string.
    :return: Environment variable value, or None if it's unset and required = False.
    """
    value = os.environ.get(name, None)

    if value is None:

        if required:
            raise McConfigEnvironmentVariableUnsetException(f"Environment variable '{name}' is unset.")

    else:

        if value == '':
            if not allow_empty_string:
                raise McConfigEnvironmentVariableUnsetException(f"Environment variable '{name}' is empty.")

    return value


def file_with_env_value(name: str, allow_empty_string: bool = False, encoded_with_base64: bool = False) -> str:
    """
    Write the value of an environment variable to a temporary file and return a path to it.

    Will raise if an environment variable is not set.

    Useful for using APIs which insist on reading its configuration from a file, e.g. Google Cloud API.

    :param name: Environment variable name.
    :param allow_empty_string: If False, will raise if environment variable is set to an empty string.
    :param encoded_with_base64: If True, environment variable's contents will be decoded from Base64.
    :return: Path to a temporary file with environment variable value's contents.
    """

    value = env_value(name=name, required=True, allow_empty_string=allow_empty_string)

    if encoded_with_base64:
        value = value.strip()
        value = base64.b64decode(value)
    else:
        # Convert to 'bytes' in any case
        value = value.encode('utf-8')

    # Always store the environment variable under the same name in order not to litter the temporary directory with a
    # bunch of random files created on every call to this function
    value_sha1 = hashlib.sha1(value).hexdigest()
    temp_file_path = os.path.join(tempfile.gettempdir(), f"{value_sha1}")

    # Always overwrite the contents of the file because the last write might have failed for whatever reason
    with open(temp_file_path, mode='wb') as f:
        f.write(value)

    return temp_file_path
