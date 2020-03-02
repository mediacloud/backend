import abc
import socket
from typing import Callable, Type, Any

import celery
from celery.result import AsyncResult
from kombu import Exchange, Queue

from mediawords.util.config.common import CommonConfig
from mediawords.util.log import create_logger

log = create_logger(__name__)


class _WorkerTask(celery.Task):
    """Wrapper for Celery tasks."""

    __slots__ = [
        '__queue_name',
        '__handler',
    ]

    def __init__(self, queue_name: str, handler: Callable):
        assert queue_name, "Queue name is unset."
        assert handler, "Handler is unset."
        self.__queue_name = queue_name
        self.__handler = handler

    @property
    def name(self) -> str:
        """(Celery) Task's name."""
        return self.__queue_name

    @name.setter
    def name(self, name: str) -> None:
        """(Celery) Task's name."""
        assert False, "Name is supposed to be constant."

    def run(self, *args, **kwargs) -> Any:
        """(Celery) Run task."""
        return_value = None
        try:
            log.info("Running job {job_name} with args: {args}, kwargs: {kwargs}...".format(
                job_name=self.__queue_name,
                args=str(args),
                kwargs=str(kwargs),
            ))
            return_value = self.__handler(*args, **kwargs)

        except Exception as ex:
            log.error("Failed running job {job_name} with args: {args}, kwargs: {kwargs}: {exception}".format(
                job_name=self.__queue_name,
                args=str(args),
                kwargs=str(kwargs),
                exception=str(ex),
            ))
            raise ex

        else:
            log.info("Finished running job {job_name} with args: {args}, kwargs: {kwargs}.".format(
                job_name=self.__queue_name,
                args=str(args),
                kwargs=str(kwargs),
            ))

        return return_value


class JobBroker(object):
    """Job broker class."""

    __slots__ = [
        # celery.Celery instance
        '__app',

        # Queue name
        '__queue_name',
    ]

    def __init__(self, queue_name: str):
        """Return job broker (Celery app object) prepared for the specific queue name."""

        assert queue_name, "Queue name is empty."
        self.__queue_name = queue_name

        config = CommonConfig()

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

    def __result_for_task(self, args: tuple, kwargs: dict) -> AsyncResult:
        return self.__app.send_task(self.__queue_name, args=args, kwargs=kwargs)

    def run_remotely(self, *args, **kwargs) -> Any:
        """Run job remotely, return the result."""
        result = self.__result_for_task(args=args, kwargs=kwargs)

        # As per http://docs.celeryq.org/en/latest/userguide/tasks.html#task-synchronous-subtasks,
        # synchronous sub-tasks are not super-awesome, but some tests use them,
        # e.g. test_topics_mine.t calls topics_fetch_link worker and it
        # extracts the fetched link with extract_and_vector worker, thus
        # building up this chain of operations.
        #
        # Let's only hope someone refactors this one day!
        disable_sync_subtasks = False

        return result.get(disable_sync_subtasks=disable_sync_subtasks)

    def add_to_queue(self, *args, **kwargs) -> str:
        """Add job to queue, return job ID."""
        result = self.__result_for_task(args=args, kwargs=kwargs)
        return result.id

    def start_worker(self, handler: Callable):
        """Start handling jobs for the configured queue using a specified callable handler."""

        task = self.__app.register_task(_WorkerTask(queue_name=self.__queue_name, handler=handler))

        node_name = '{name}@{hostname}'.format(
            name=self.__queue_name,
            hostname=socket.gethostname(),
        )
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
