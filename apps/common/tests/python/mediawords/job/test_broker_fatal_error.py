import time
from typing import List, Type

from mediawords.job import JobBroker
from mediawords.util.log import create_logger

from .setup_broker_test import AbstractBrokerTestCase, Worker

log = create_logger(__name__)


class TestBrokerFatalError(AbstractBrokerTestCase):

    @classmethod
    def worker_paths(cls) -> List[Worker]:
        workers_path = '/opt/mediacloud/tests/python/mediawords/job/test_broker_fatal_error'

        return [
            Worker(
                queue_name='TestPerlWorkerFatalError',
                worker_path=f"{workers_path}/perl_worker.pl",
            ),
            Worker(
                queue_name='TestPythonWorkerFatalError',
                worker_path=f"{workers_path}/python_worker.py"
            ),
        ]

    @classmethod
    def broker_class(cls) -> Type[JobBroker]:
        return JobBroker

    def test_fatal_error(self):

        for worker in self.WORKERS:

            worker.app.add_to_queue()

            return_code = None
            for retry in range(20):
                log.info(f"Waiting for the process {worker.processes[0].pid} to stop (retry {retry})...")
                return_code = worker.processes[0].poll()
                if return_code is not None:
                    log.info(f"Process stopped with return code {return_code}")
                    break
                time.sleep(0.5)

            assert return_code is not None, "Process has managed to stop."
            assert return_code != 0, f"Process returned non-zero exit code {return_code}."
