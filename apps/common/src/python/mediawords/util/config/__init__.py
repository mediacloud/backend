import os
from typing import Optional


class McConfigException(Exception):
    """Configuration exception."""
    pass


class McConfigEnvironmentVariableUnsetException(McConfigException):
    """Exception that is raised when an environment variable is unset."""
    pass


def env_value(name: str, required: bool = True, allow_empty_string: bool = False) -> Optional[str]:
    """Return value of an environment variable, raise if it's required.

    There are 4 types of configuration properties:

    * required; must be a non-empty string
    * required; can be an empty string
    * optional; must be a non-empty string when set
    * optional; can be an empty string when set
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
