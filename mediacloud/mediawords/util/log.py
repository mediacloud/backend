import logging
import os


class Logger(object):
    """Logger class.

    See doc/logging.markdown for usage example."""

    # Environment variable to read the custom logging level from
    __logging_level_env_variable = 'MC_LOGGING_LEVEL'

    # Valid logging levels and their "logging" counterparts
    __logging_levels = {
        'CRITICAL': logging.CRITICAL,
        'ERROR': logging.ERROR,
        'WARNING': logging.WARNING,
        'INFO': logging.INFO,
        'DEBUG': logging.DEBUG,
    }

    # Default logging level (used when environment variable is not set)
    __default_logging_level = 'INFO'

    # "logging" object
    __l = None

    def __init__(self, name: str):
        """Initialize logger object for a given name."""
        # noinspection SpellCheckingInspection

        self.__l = logging.getLogger(name)
        if not self.__l.handlers:
            formatter = logging.Formatter(
                fmt='%(asctime)s %(levelname)s %(name)s [%(process)d/%(threadName)s]: %(message)s'
            )

            handler = logging.StreamHandler()
            handler.setFormatter(formatter)
            self.__l.addHandler(handler)

            logging_level = os.environ.get(self.__logging_level_env_variable, self.__default_logging_level)
            if logging_level not in self.__logging_levels:
                self.warning("Logging level '%s' is invalid, resetting to default '%s'" % (
                    logging_level, self.__default_logging_level
                ))
                logging_level = self.__default_logging_level

            self.__l.setLevel(self.__logging_levels[logging_level])

            # Don't propagate handler to root logger
            # (http://stackoverflow.com/a/21127526/200603)
            self.__l.propagate = False

    def error(self, message: str) -> None:
        """Log error message."""
        self.__l.error(message)

    def warning(self, message: str) -> None:
        """Log warning message."""
        self.__l.warning(message)

    def info(self, message: str) -> None:
        """Log informational message."""
        self.__l.info(message)

    def debug(self, message: str) -> None:
        """Log debugging message."""
        self.__l.debug(message)


def create_logger(name: str) -> Logger:
    """Create and return Logger object."""
    return Logger(name=name)
