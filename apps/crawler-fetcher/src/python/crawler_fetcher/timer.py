from timeit import default_timer as timer

from mediawords.util.log import create_logger

log = create_logger(__name__)


class Timer(object):
    """Measure time it takes to do something."""

    __slots__ = [
        '__label',
        '__start_time',
    ]

    def __init__(self, label: str):
        self.__label = label
        self.__start_time = None

    def start(self) -> 'Timer':
        if self.__start_time:
            log.warning(f"Timer '{self.__label}' is already started.")
            self.stop()
        log.info(f"Starting timer '{self.__label}'...")
        self.__start_time = timer()

        # So that one can do: timer = Timing('label').start()
        return self

    def stop(self) -> float:
        if not self.__start_time:
            f"Timer '{self.__label}' was not started."
            return 0.00
        elapsed = timer() - self.__start_time
        log.info(f"Stopped timer '{self.__label}' after {elapsed:.2f} seconds")
        self.__start_time = None
        return elapsed
