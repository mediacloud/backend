import os


class McConfigException(Exception):
    """Configuration exception."""
    pass


class McConfigEnvironmentVariableUnsetException(McConfigException):
    """Exception that is raised when an environment variable is unset."""
    pass


def env_value_or_raise(name: str, allow_empty_string: bool = False) -> str:
    """Return value of an environment variable or raise an exception if it's unset / empty."""
    value = os.environ.get(name, None)
    if value is None:
        raise McConfigEnvironmentVariableUnsetException("Environment variable '{}' is unset.".format(name))
    if (not allow_empty_string) and value == '':
        raise McConfigEnvironmentVariableUnsetException("Environment variable '{}' is empty.".format(name))
    return value
