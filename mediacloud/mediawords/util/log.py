import logging


class Logger(object):
    """Logger class."""

    # Default logging level
    __default_logging_level = logging.INFO

    # "logging" object
    __l = None

    def __init__(self, name: str):
        """Initialize logger object for a given name."""
        # noinspection SpellCheckingInspection

        self.__l = logging.getLogger(name)
        if not self.__l.handlers:
            formatter = logging.Formatter(fmt='%(asctime)s - %(levelname)s - %(module)s - %(message)s')

            handler = logging.StreamHandler()
            handler.setFormatter(formatter)

            self.__l.setLevel(self.__default_logging_level)
            self.__l.addHandler(handler)

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
