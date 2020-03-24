import time
from typing import List, Type

from mediawords.job import JobBroker
from mediawords.util.log import create_logger

from .setup_broker_test import AbstractBrokerTestCase, Worker

log = create_logger(__name__)


class TestBrokerLock(AbstractBrokerTestCase):

    @classmethod
    def worker_paths(cls) -> List[Worker]:
        workers_path = '/opt/mediacloud/tests/python/mediawords/job/test_broker_lock'

        # Need 2+ workers to see the effect of locking
        worker_count = 2

        return [
            Worker(
                queue_name='TestPerlWorkerLock',
                worker_path=f"{workers_path}/perl_worker.pl",
                worker_count=worker_count,
            ),
            Worker(
                queue_name='TestPythonWorkerLock',
                worker_path=f"{workers_path}/python_worker.py",
                worker_count=worker_count,
            ),
        ]

    @classmethod
    def broker_class(cls) -> Type[JobBroker]:
        return JobBroker

    def test_lock(self):
        lock_test_id = 123

        for worker in self.WORKERS:
            log.info("Adding the first job to the queue which will take 10+ seconds to run...")
            job_id = worker.app.add_to_queue(test_id=lock_test_id, x=2, y=3)

            log.info("Waiting for the job to reach the queue...")
            time.sleep(2)

            # While assuming that the first job is currently running (and thus is "locked"):
            log.info("Testing if a subsequent job fails with a lock problem...")
            assert worker.app.run_remotely(test_id=lock_test_id, x=3, y=4) is None, "Second job shouldn't work"

            log.info("Waiting for the first job to finish...")
            assert worker.app.get_result(job_id=job_id) == 5
