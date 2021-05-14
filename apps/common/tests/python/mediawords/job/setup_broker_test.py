import abc
import dataclasses
import os
import subprocess
from typing import List, Type
from unittest import TestCase

from mediawords.job import JobBroker
from mediawords.util.log import create_logger

log = create_logger(__name__)


@dataclasses.dataclass
class Worker(object):
    queue_name: str
    """Worker queue name, e.g. "TestPerlWorker"."""

    worker_path: str
    """Worker script path, e.g. "/opt/mediacloud/tests/python/mediawords/job/test_broker/perl_worker.pl"."""

    worker_count: int = 1
    """How many workers to start."""


@dataclasses.dataclass
class _RunningWorker(object):
    app: JobBroker
    """JobBroker instance."""

    processes: List[subprocess.Popen]
    """Running processes."""


class AbstractBrokerTestCase(TestCase, metaclass=abc.ABCMeta):
    WORKERS = []  # type: List[_RunningWorker]
    """_RunningWorker instances"""

    @classmethod
    @abc.abstractmethod
    def worker_paths(cls) -> List[Worker]:
        raise NotImplementedError("Abstract method")

    @classmethod
    @abc.abstractmethod
    def broker_class(cls) -> Type[JobBroker]:
        raise NotImplementedError("Abstract method")

    @classmethod
    def setUpClass(cls) -> None:

        for worker in cls.worker_paths():
            assert os.path.isfile(worker.worker_path), f"Worker script exists at {worker.worker_path}"
            assert os.access(worker.worker_path, os.X_OK), f"Worker script is executable at {worker.worker_path}"

            broker_class = cls.broker_class()
            worker_app = broker_class(queue_name=worker.queue_name)

            processes = []

            assert worker.worker_count > 0, "Worker count has to be positive"

            for x in range(worker.worker_count):
                worker_process = subprocess.Popen([worker.worker_path])
                assert worker_process.poll() is None, f"Worker process #{x} is still running at {worker.worker_path}"

                processes.append(worker_process)

            cls.WORKERS.append(_RunningWorker(app=worker_app, processes=processes))

    @classmethod
    def tearDownClass(cls) -> None:
        log.info("Killing workers")
        for worker in cls.WORKERS:
            for process in worker.processes:
                log.info(f"Killing worker with PID {process.pid}")
                process.terminate()
