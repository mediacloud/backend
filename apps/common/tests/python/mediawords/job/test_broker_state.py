import dataclasses
import socket
import time
from typing import List, Optional, Type

from mediawords.db import connect_to_db
from mediawords.job import JobBroker, StatefulJobBroker
from mediawords.job.states import STATE_COMPLETED, STATE_ERROR, STATE_RUNNING
from mediawords.util.log import create_logger
from mediawords.util.parse_json import decode_json

from .setup_broker_test import AbstractBrokerTestCase, Worker

log = create_logger(__name__)


class TestBrokerState(AbstractBrokerTestCase):

    @classmethod
    def worker_paths(cls) -> List[Worker]:
        workers_path = '/opt/mediacloud/tests/python/mediawords/job/test_broker_state'

        return [

            Worker(
                queue_name='TestPerlWorkerStateCompleted',
                worker_path=f"{workers_path}/perl_worker_completed.pl"
            ),
            Worker(
                queue_name='TestPerlWorkerStateCustom',
                worker_path=f"{workers_path}/perl_worker_custom.pl"
            ),
            Worker(
                queue_name='TestPerlWorkerStateError',
                worker_path=f"{workers_path}/perl_worker_error.pl"
            ),
            Worker(
                queue_name='TestPerlWorkerStateRunning',
                worker_path=f"{workers_path}/perl_worker_running.pl"
            ),

            Worker(
                queue_name='TestPythonWorkerStateCompleted',
                worker_path=f"{workers_path}/python_worker_completed.py"
            ),
            Worker(
                queue_name='TestPythonWorkerStateCustom',
                worker_path=f"{workers_path}/python_worker_custom.py"
            ),
            Worker(
                queue_name='TestPythonWorkerStateError',
                worker_path=f"{workers_path}/python_worker_error.py"
            ),
            Worker(
                queue_name='TestPythonWorkerStateRunning',
                worker_path=f"{workers_path}/python_worker_running.py"
            ),

        ]

    @classmethod
    def broker_class(cls) -> Type[JobBroker]:
        return StatefulJobBroker

    @dataclasses.dataclass
    class _WorkerTypeToTest(object):
        queue_name_ends_with: str
        expected_result: Optional[int]
        expected_state: str
        expected_message: str

    @classmethod
    def setUpClass(cls) -> None:
        cls.DB = connect_to_db()

        cls.DB.query("""
            CREATE TABLE IF NOT EXISTS test_job_states (
                test_job_states_id  SERIAL  PRIMARY KEY,
                state               TEXT    NOT NULL,
                message             TEXT    NOT NULL
            );
        """)

        # Clean up leftovers from previous runs
        # noinspection SqlWithoutWhere
        cls.DB.query("DELETE FROM job_states")
        # noinspection SqlResolve,SqlWithoutWhere
        cls.DB.query("DELETE FROM test_job_states")

        super().setUpClass()

    def test_state(self):

        common_kwargs = {'x': 2, 'y': 3}
        expected_result = common_kwargs['x'] + common_kwargs['y']

        worker_types = [
            self._WorkerTypeToTest(
                queue_name_ends_with='Completed',
                expected_result=expected_result,
                expected_state=STATE_COMPLETED,
                expected_message='',
            ),
            self._WorkerTypeToTest(
                queue_name_ends_with='Custom',
                expected_result=None,  # never finishes
                expected_state='foo',
                expected_message='bar',
            ),
            self._WorkerTypeToTest(
                queue_name_ends_with='Error',
                expected_result=None,  # fails
                expected_state=STATE_ERROR,
                expected_message="Well, it didn't work",
            ),
            self._WorkerTypeToTest(
                queue_name_ends_with='Running',
                expected_result=None,  # never finishes
                expected_state=STATE_RUNNING,
                expected_message='',
            ),
        ]

        for worker_type in worker_types:

            for worker in [w for w in self.WORKERS if w.app.queue_name().endswith(worker_type.queue_name_ends_with)]:
                # noinspection SqlResolve,SqlWithoutWhere
                self.DB.query("DELETE FROM test_job_states")

                test_job_state = self.DB.insert(table='test_job_states', insert_hash={
                    'state': '',
                    'message': '',
                })
                test_job_states_id = test_job_state['test_job_states_id']

                kwargs = {**common_kwargs, **{'test_job_states_id': test_job_states_id}}

                job_id = worker.app.add_to_queue(**kwargs)

                if worker_type.expected_result is None:
                    # Just wait a bit for the thing to finish
                    time.sleep(5)
                else:
                    result = worker.app.get_result(job_id=job_id)
                    assert result == expected_result, f"Result for worker {worker}"

                job_states = self.DB.query("""
                    SELECT *
                    FROM job_states
                    WHERE class = %(queue_name)s
                """, {'queue_name': worker.app.queue_name()}).hashes()
                assert len(job_states) == 1, f"Job state count for worker {worker}"

                job_state = job_states[0]

                assert job_state['state'] == worker_type.expected_state, f"Job state for worker {worker}"
                assert worker_type.expected_message in job_state['message'], f"Job message for worker {worker}"
                assert job_state['last_updated'], f"Job's last updated for worker {worker}"
                assert decode_json(job_state['args']) == kwargs, f"Job's arguments for worker {worker}"
                assert job_state['hostname'] == socket.gethostname(), f"Job's hostname for worker {worker}"

                custom_table_states = self.DB.select(table='test_job_states', what_to_select='*').hashes()
                assert len(custom_table_states) == 1, f"Custom table states count for worker {worker}"
                custom_table_state = custom_table_states[0]

                assert custom_table_state['state'] == worker_type.expected_state, (
                    f"Custom table state for worker {worker}"
                )
                assert worker_type.expected_message in custom_table_state['message'], (
                    f"Custom table message for worker {worker}"
                )
