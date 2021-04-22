import os
import socket
from typing import Callable, Any, Optional, Dict, List

import celery
from celery.result import AsyncResult
from celery.exceptions import TimeoutError
from kombu import Exchange, Queue

from mediawords.db import connect_to_db, DatabaseHandler
from mediawords.db.locks import get_session_lock, release_session_lock
from mediawords.job.states import STATE_QUEUED, STATE_RUNNING, STATE_COMPLETED, STATE_ERROR
from mediawords.util.config.common import CommonConfig, RabbitMQConfig
from mediawords.util.log import create_logger
from mediawords.util.parse_json import encode_json, decode_json
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.sql import sql_now

log = create_logger(__name__)


class McJobBrokerGetResultTimeoutException(Exception):
    """Exception thrown when get_result() times out while waiting for result."""
    pass


class McStatefulJobBrokerStateUnconfiguredException(Exception):
    """Exception thrown when StatefulJobBroker's state is unconfigured."""
    pass


class JobLock(object):
    """Job lock configuration."""

    __slots__ = [
        '__lock_type',
        '__lock_arg',
    ]

    def __init__(self, lock_type: str, lock_arg: str):
        lock_type = decode_object_from_bytes_if_needed(lock_type)
        lock_arg = decode_object_from_bytes_if_needed(lock_arg)

        assert lock_type, "Lock type is not set."
        assert lock_arg, "Lock argument is not set."

        self.__lock_type = lock_type
        self.__lock_arg = lock_arg

    def lock_type(self) -> str:
        """Return lock type, e.g. "MediaWords::Job::TM::SnapshotTopic"."""
        return self.__lock_type

    def lock_arg(self) -> str:
        """Return lock argument, e.g. "topics_id"."""
        return self.__lock_arg


class JobStateExtraTable(object):
    """Job state configuration for reporting state to an extra table."""

    __slots__ = [
        '__table_name',
        '__state_column',
        '__message_column',
    ]

    def __init__(self, table_name: str, state_column: str, message_column: str):
        table_name = decode_object_from_bytes_if_needed(table_name)
        state_column = decode_object_from_bytes_if_needed(state_column)
        message_column = decode_object_from_bytes_if_needed(message_column)

        assert table_name, "Extra state table name is not set."
        assert state_column, "Extra state column is not set."
        assert message_column, "Extra message column is not set."

        self.__table_name = table_name
        self.__state_column = state_column
        self.__message_column = message_column

    def table_name(self) -> str:
        """Return table name where extra state will be stored, e.g. "retweeter_scores"."""
        return self.__table_name

    def state_column(self) -> str:
        """Return table column name where extra state will be stored, e.g. "state"."""
        return self.__state_column

    def message_column(self) -> str:
        """Return table column name where message will be stored, e.g. "message"."""
        return self.__message_column


class JobState(object):
    """Job state configuration."""

    __slots__ = [
        '__extra_table',
    ]

    def __init__(self, extra_table: Optional[JobStateExtraTable] = None):
        """
        Constructor.

        :param extra_table: (Optional) If set, state will be reported to one extra table in addition to "job_states".
        """
        if extra_table:
            assert isinstance(extra_table, JobStateExtraTable)

        self.__extra_table = extra_table

    def extra_table(self) -> Optional[JobStateExtraTable]:
        """Return extra table state configuration if it's set or None otherwise."""
        return self.__extra_table


def _create_queued_job_state(db: DatabaseHandler, queue_name: str, args: Dict[str, Any]) -> Dict[str, Any]:
    """Create the initial entry in the "job_states" table with a state of 'queued' and return it."""
    queue_name = decode_object_from_bytes_if_needed(queue_name)
    args = decode_object_from_bytes_if_needed(args)

    args_json = encode_json(args)

    state = db.create(table='job_states', insert_hash={
        'state': STATE_QUEUED,
        'args': args_json,
        'priority': 'normal',
        'class': queue_name,
        'process_id': os.getpid(),
        'hostname': socket.gethostname(),
    })

    return state


class StateUpdater(object):
    __slots__ = [
        '__queue_name',
        '__job_states_id',
        '__state_config',
    ]

    def __init__(self, queue_name: str, job_states_id: int, state_config: JobState):
        queue_name = decode_object_from_bytes_if_needed(queue_name)

        if isinstance(job_states_id, bytes):
            job_states_id = decode_object_from_bytes_if_needed(job_states_id)

        if job_states_id:
            job_states_id = int(job_states_id)

        assert queue_name, "Queue name is unset."
        assert job_states_id, "Job state ID is unset."
        assert state_config, "State configuration is unset."

        self.__queue_name = queue_name
        self.__job_states_id = job_states_id
        self.__state_config = state_config

    def __update_table_state(self, db: DatabaseHandler, job_state: Dict[str, Any]) -> None:
        """
        Update the state and message fields in the given table for the row whose '<table>_id' field matches that field
        in the job args.
        """
        job_state = decode_object_from_bytes_if_needed(job_state)

        try:
            args = decode_json(job_state.get('args', ''))
        except Exception as ex:
            log.error(f"Unable to decode args from job state {job_state}: {ex}")
            return

        extra_table = self.__state_config.extra_table()
        if extra_table:

            id_field = extra_table.table_name() + '_id'
            id_value = args.get(id_field, None)
            if not id_value:
                # Sometimes there is not a relevant <table>_id until some of the code in run() has run, for instance
                # SnapshotTopic needs to create the snapshot.
                log.warning(f"Unable to get ID value for field '{id_field}' from job state {job_state}")
                return None

            update = {
                extra_table.state_column(): job_state.get('state', None),
                extra_table.message_column(): job_state.get('message', None),
            }

            db.update_by_id(table=extra_table.table_name(), object_id=id_value, update_hash=update)

        else:
            log.debug("Extra table for storing state is not configured.")

    def update_job_state(self, db: DatabaseHandler, state: str, message: Optional[str] = ''):
        """
        Update the state and message fields of the "job_states" table for the currently active "job_states_id".

        "jobs_states_id" is set and unset in method run() below, so this must be called from code running from within
        the run() implementation of the subclass.
        """
        state = decode_object_from_bytes_if_needed(state)
        message = decode_object_from_bytes_if_needed(message)

        log.debug(f"{self.__queue_name} state: {state}")

        job_state = db.update_by_id(table='job_states', object_id=self.__job_states_id, update_hash={
            'state': state,
            'last_updated': sql_now(),
            'message': message,
        })

        self.__update_table_state(db=db, job_state=job_state)

    def update_job_state_args(self, db: DatabaseHandler, args: Dict[str, Any]) -> None:
        """Update the args field for the current "job_states" row."""
        args = decode_object_from_bytes_if_needed(args)

        job_state = db.require_by_id(table='job_states', object_id=self.__job_states_id)

        try:
            db_args = decode_json(job_state.get('args', '{}'))
        except Exception as ex:
            log.error(f"Unable to decode args from job state {job_state}: {ex}")
            db_args = {}

        db_args = {**db_args, **args}

        args_json = encode_json(db_args)

        db.update_by_id(table='job_states', object_id=self.__job_states_id, update_hash={
            'args': args_json,
        })

    def update_job_state_message(self, db: DatabaseHandler, message: str) -> None:
        """
        Update the message field for the current "job_states" row.

        This is a public method that is intended to be used by code run anywhere above the stack from run() to publish
        messages updating the progress of a long running job.
        """
        message = decode_object_from_bytes_if_needed(message)

        # Verify that it exists I guess?
        db.require_by_id(table='job_states', object_id=self.__job_states_id)

        job_state = db.update_by_id(table='job_states', object_id=self.__job_states_id, update_hash={
            'message': message,
            'last_updated': sql_now(),
        })

        self.__update_table_state(db=db, job_state=job_state)


class _WorkerTask(celery.Task):
    """Wrapper for Celery tasks."""

    __slots__ = [
        '__queue_name',
        '__handler',
        '__lock',
        '__state',
    ]

    def __init__(self,
                 queue_name: str,
                 handler: Callable,
                 lock: Optional[JobLock] = None,
                 state: Optional[JobState] = None):

        queue_name = decode_object_from_bytes_if_needed(queue_name)

        assert queue_name, "Queue name is unset."
        assert handler, "Handler is unset."
        self.__queue_name = queue_name
        self.__handler = handler
        self.__lock = lock
        self.__state = state

    @property
    def name(self) -> str:
        """(Celery) Task's name."""
        return self.__queue_name

    # noinspection PyUnusedLocal
    @name.setter
    def name(self, name: str) -> None:
        """(Celery) Task's name."""
        assert False, "Name is supposed to be constant."

    def run(self, *args, **kwargs) -> Any:
        """(Celery) Run task."""

        args = decode_object_from_bytes_if_needed(args)
        kwargs = decode_object_from_bytes_if_needed(kwargs)

        db = None
        if self.__lock or self.__state:
            db = connect_to_db()

        state_updater = None
        if self.__state:

            job_states_id = kwargs.get('job_states_id', None)

            if job_states_id:
                del kwargs['job_states_id']
            else:
                job_state = _create_queued_job_state(db=db, queue_name=self.__queue_name, args=kwargs)
                job_states_id = job_state['job_states_id']

            state_updater = StateUpdater(
                queue_name=self.__queue_name,
                job_states_id=job_states_id,
                state_config=self.__state,
            )

        lock_type = None
        lock_id = None
        if self.__lock:

            lock_type = self.__lock.lock_type()
            lock_id = int(kwargs.get(self.__lock.lock_arg(), 0))

            if not get_session_lock(db=db, lock_type=lock_type, lock_id=lock_id, wait=False):
                message = (
                    f"Job with type '{lock_type}' "
                    f"and argument {self.__lock.lock_arg()} = {lock_id} is already running. "
                    f"Skipping this job..."
                )
                log.warning(message)

                if self.__state:
                    state_updater.update_job_state(db=db, state=STATE_ERROR, message=message)

                return None

        if self.__state:
            state_updater.update_job_state(db=db, state=STATE_RUNNING)

        job_ex = None
        return_value = None

        try:

            if self.__state:
                kwargs['state_updater'] = state_updater

            log.info(f"Running job {self.__queue_name} with args: {args}, kwargs: {kwargs}...")
            return_value = self.__handler(*args, **kwargs)

        except Exception as ex:
            log.error(f"Failed running job {self.__queue_name} with args: {args}, kwargs: {kwargs}: {ex}")

            if self.__state:
                state_updater.update_job_state(db=db, state=STATE_ERROR, message=str(ex))

            job_ex = ex

        else:
            log.info(f"Finished running job {self.__queue_name} with args: {args}, kwargs: {kwargs}.")

            if self.__state:
                state_updater.update_job_state(db=db, state=STATE_COMPLETED)

        if self.__lock:
            release_session_lock(db=db, lock_type=lock_type, lock_id=lock_id)

        if job_ex:
            raise job_ex
        else:
            return return_value


class JobBroker(object):
    """Job broker."""

    __slots__ = [
        # celery.Celery instance
        '__app',

        # Queue name
        '__queue_name',
    ]

    def __init__(self, queue_name: str, rabbitmq_config: Optional[RabbitMQConfig] = None):
        """
        Create job broker object.

        :param queue_name: Queue name.
        """

        queue_name = decode_object_from_bytes_if_needed(queue_name)

        assert queue_name, "Queue name is empty."

        self.__queue_name = queue_name

        config = CommonConfig()

        if not rabbitmq_config:
            rabbitmq_config = config.rabbitmq()

        broker_uri = 'amqp://{username}:{password}@{hostname}:{port}/{vhost}'.format(
            username=rabbitmq_config.username(),
            password=rabbitmq_config.password(),
            hostname=rabbitmq_config.hostname(),
            port=rabbitmq_config.port(),
            vhost=rabbitmq_config.vhost(),
        )

        db_config = CommonConfig.database()
        result_backend_url = 'db+postgresql+psycopg2://{username}:{password}@{hostname}:{port}/{database}'.format(
            username=db_config.username(),
            password=db_config.password(),
            hostname=db_config.hostname(),
            port=db_config.port(),
            database=db_config.database_name(),
        )

        self.__app = celery.Celery(queue_name, broker=broker_uri, backend=result_backend_url)

        self.__app.conf.broker_connection_timeout = rabbitmq_config.timeout()

        # Concurrency is done by us, not Celery itself
        self.__app.conf.worker_concurrency = 1

        self.__app.conf.broker_heartbeat = 0

        # Acknowledge tasks after they get run, not before
        self.__app.conf.task_acks_late = 1

        # https://tech.labs.oliverwyman.com/blog/2015/04/30/making-celery-play-nice-with-rabbitmq-and-bigwig/
        self.__app.conf.broker_transport_options = {'confirm_publish': True}

        self.__app.conf.database_table_names = {
            'task': 'celery_tasks',
            'group': 'celery_groups',
        }

        # Fetch only one job at a time
        self.__app.conf.worker_prefetch_multiplier = 1

        self.__app.conf.worker_max_tasks_per_child = 1000

        retries_config = rabbitmq_config.retries()
        if retries_config:
            self.__app.task_publish_retry = True
            self.__app.task_publish_retry_policy = {
                'max_retries': retries_config.max_retries(),
                'interval_start': retries_config.interval_start(),
                'interval_step': retries_config.interval_step(),
                'interval_max': retries_config.interval_max(),
            }

        else:
            self.__app.task_publish_retry = False

        queue = Queue(
            name=queue_name,
            exchange=Exchange(queue_name),
            routing_key=queue_name,
            queue_arguments={
                'x-max-priority': 3,
                'x-queue-mode': 'lazy',
            },
        )
        self.__app.conf.task_queues = [queue]

        # noinspection PyUnusedLocal
        def __route_task(name, args_, kwargs_, options_, task_=None, **kw_):
            return {
                'queue': name,
                'exchange': name,
                'routing_key': name,
            }

        self.__app.conf.task_routes = (__route_task,)

    def queue_name(self) -> str:
        return self.__queue_name

    def __send_task(self, args: Optional[List[Any]], kwargs: Optional[Dict[str, Any]]) -> str:
        args = decode_object_from_bytes_if_needed(args)
        kwargs = decode_object_from_bytes_if_needed(kwargs)

        result = self.__app.send_task(self.__queue_name, args=args, kwargs=kwargs)

        job_id = result.id

        return job_id

    def add_to_queue(self, *args, **kwargs) -> str:
        """
        Add job to queue and return its job ID.

        :param args: (DO NOT USE!) List of arguments to pass to the job.
        :param kwargs: Dictionary of named arguments to pass to the job.
        :return: Job ID to be potentially used by get_result().
        """
        args = decode_object_from_bytes_if_needed(args)
        kwargs = decode_object_from_bytes_if_needed(kwargs)

        return self.__send_task(args=args, kwargs=kwargs)

    @classmethod
    def get_result(cls, job_id: str, timeout: Optional[int] = None) -> Any:
        """
        Fetch result of a job previously added with add_to_queue().

        :param job_id: Job ID returned by add_to_queue().
        :param timeout: If set, wait for job result only for a defined number of seconds.
        :return: Job result; throws McJobBrokerGetResultTimeoutException if timeout is set and expires.
        """
        job_id = decode_object_from_bytes_if_needed(job_id)

        if isinstance(timeout, bytes):
            timeout = decode_object_from_bytes_if_needed(timeout)

        if timeout is not None:
            timeout = int(timeout)

        result = AsyncResult(job_id)

        # As per http://docs.celeryq.org/en/latest/userguide/tasks.html#task-synchronous-subtasks,
        # synchronous sub-tasks are not super-awesome, but some tests use them, e.g. test_topics_mine.t calls
        # topics_fetch_link worker and it extracts the fetched link with extract_and_vector worker, thus building up
        # this chain of operations.
        #
        # Let's only hope someone refactors this one day!
        disable_sync_subtasks = False

        try:
            r = result.get(disable_sync_subtasks=disable_sync_subtasks, timeout=timeout)
        except TimeoutError:
            raise McJobBrokerGetResultTimeoutException(f"Timed out while waiting for result; job ID: {job_id}")
        except Exception as ex:
            raise ex

        return r

    def run_remotely(self, *args, **kwargs) -> Any:
        """
        Add job to queue, wait for it to finish and return its result (return value).

        :param args: (DO NOT USE!) List of arguments to pass to the job.
        :param kwargs: Dictionary of named arguments to pass to the job.
        :return: Job's result (return value).
        """
        args = decode_object_from_bytes_if_needed(args)
        kwargs = decode_object_from_bytes_if_needed(kwargs)

        job_id = self.__send_task(args=args, kwargs=kwargs)

        result = self.get_result(job_id=job_id)

        return result

    def _start_worker_impl(self, handler: Callable, lock: Optional[JobLock] = None, state: Optional[JobState] = None):
        assert handler, "Job handler is not set."

        task = _WorkerTask(queue_name=self.__queue_name, handler=handler, lock=lock, state=state)
        self.__app.register_task(task)

        node_name = f'{self.__queue_name}@{socket.gethostname()}'
        log.info(f"Starting worker {node_name}...")
        self.__app.worker_main(argv=[
            'worker',
            '--loglevel', 'info',
            '--hostname', node_name,

            # It would be nice to use "solo" pool (--pool=solo) to work around worker stalls:
            #
            #     https://github.com/celery/celery/issues/3759#issuecomment-311763355
            #
            # but then long-running tasks get executed multiple times:
            #
            #     https://github.com/celery/celery/issues/3430

            # Workers aren't expected to interact much, and their heartbeats is just noise (and probably error prone)
            '--without-gossip',
            '--without-mingle',
        ])

    def start_worker(self, handler: Callable, lock: Optional[JobLock] = None):
        """
        Start handling jobs for the configured queue using a specified callable handler.

        Handler function should expect arguments to be passed as kwargs.

        :param handler: Function that will be handling the jobs.
        :param lock: (Optional) Job lock configuration to prevent parallel jobs with identical arguments.
        """
        self._start_worker_impl(handler=handler, lock=lock, state=None)


class StatefulJobBroker(JobBroker):
    """Job broker that preserves state."""

    __slots__ = [
        '__db',
    ]

    def __init__(self, queue_name: str):
        queue_name = decode_object_from_bytes_if_needed(queue_name)

        super().__init__(queue_name=queue_name)

        self.__db = connect_to_db()

    def __kwargs_with_job_states_id(self, kwargs: Dict[str, Any]) -> Dict[str, Any]:
        kwargs = decode_object_from_bytes_if_needed(kwargs)

        job_state = _create_queued_job_state(db=self.__db, queue_name=self.queue_name(), args=kwargs)
        kwargs['job_states_id'] = job_state['job_states_id']

        return kwargs

    def add_to_queue(self, *args, **kwargs) -> str:
        args = decode_object_from_bytes_if_needed(args)
        kwargs = decode_object_from_bytes_if_needed(kwargs)

        kwargs = self.__kwargs_with_job_states_id(kwargs=kwargs)

        return super().add_to_queue(*args, **kwargs)

    def run_remotely(self, *args, **kwargs) -> Any:
        args = decode_object_from_bytes_if_needed(args)
        kwargs = decode_object_from_bytes_if_needed(kwargs)

        kwargs = self.__kwargs_with_job_states_id(kwargs=kwargs)

        return super().run_remotely(*args, **kwargs)

    def start_worker(self, handler: Callable, lock: Optional[JobLock] = None, state: JobState = None):
        """
        Start processing stateful jobs.

        :param handler: Function that will be handling the jobs.
        :param lock: (Optional) Job lock configuration to prevent parallel jobs with identical arguments.
        :param state: Job state configuration to be able to log job state while running it.
        """

        if not state:
            raise McStatefulJobBrokerStateUnconfiguredException(
                "You're using StatefulBroker but state is not configured."
            )

        if not isinstance(state, JobState):
            raise McStatefulJobBrokerStateUnconfiguredException("Job state configuration is not JobState.")

        self._start_worker_impl(handler=handler, lock=lock, state=state)
