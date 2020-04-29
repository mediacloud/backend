from typing import List, Type

from mediawords.job import JobBroker
from mediawords.util.log import create_logger

from .setup_broker_test import AbstractBrokerTestCase, Worker

log = create_logger(__name__)


class TestBroker(AbstractBrokerTestCase):

    @classmethod
    def worker_paths(cls) -> List[Worker]:
        workers_path = '/opt/mediacloud/tests/python/mediawords/job/test_broker'

        return [
            Worker(
                queue_name='TestPerlWorker',
                worker_path=f"{workers_path}/perl_worker.pl",
            ),
            Worker(
                queue_name='TestPythonWorker',
                worker_path=f"{workers_path}/python_worker.py"
            ),
        ]

    @classmethod
    def broker_class(cls) -> Type[JobBroker]:
        return JobBroker

    def test_run_remotely(self):
        """Test run_remotely()."""
        for worker in self.WORKERS:
            result = worker.app.run_remotely(x=1, y=2)
            assert result == 3, f"Result is correct for worker {worker}"

    def test_add_to_queue_get_result(self):
        """Test add_to_queue(), get_result()."""

        for worker in self.WORKERS:
            job_id = worker.app.add_to_queue(x=3, y=4)
            log.info(f"Job ID: {job_id} for worker {worker}")

            result = worker.app.get_result(job_id=job_id)
            assert result == 7, f"Result is correct for worker {worker}"
