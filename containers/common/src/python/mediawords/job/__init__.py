import abc
import socket
import uuid
from typing import Type, Any

import celery
from celery.result import AsyncResult
from kombu import Exchange, Queue

from mediawords.util.config.common import CommonConfig
from mediawords.util.log import create_logger

log = create_logger(__name__)


class McAbstractJobException(Exception):
    """AbstractJob exception."""
    pass


class _CeleryTask(celery.Task):
    """Internal Celery task."""

    __slots__ = [
        '__job_class',
    ]

    def __init__(self, job_class: Type['AbstractJob']):
        """Constructor."""
        self.__job_class = job_class

    def run(self, *args, **kwargs) -> None:
        """(Celery) Run task."""
        return self.__job_class.run_wrapper(*args, **kwargs)

    @property
    def name(self):
        """(Celery) Task's name."""
        return self.__job_class.queue_name()

    @name.setter
    def name(self, name):
        """(Celery) Task's name."""
        raise McAbstractJobException("Name is supposed to be constant.")


class AbstractJob(object, metaclass=abc.ABCMeta):
    """Abstract job that concrete jobs should subclass and implement."""

    @classmethod
    @abc.abstractmethod
    def run_job(cls, *args, **kwargs) -> None:
        """Run job, raise on error."""
        raise NotImplementedError("Abstract method.")

    @classmethod
    @abc.abstractmethod
    def queue_name(cls) -> str:
        """Return queue name."""
        raise NotImplementedError("Abstract method.")

    # ---

    @classmethod
    def run_wrapper(cls: Type['AbstractJob'], *args, **kwargs) -> None:
        """Run job with some logging, raise on error."""

        try:
            log.info("Running job {job_name} with args: {args}, kwargs: {kwargs}...".format(
                job_name=cls.__name__,
                args=str(args),
                kwargs=str(kwargs),
            ))
            cls.run_job(*args, **kwargs)

        except Exception as ex:
            log.error("Failed running job {job_name} with args: {args}, kwargs: {kwargs}: {exception}".format(
                job_name=cls.__name__,
                args=str(args),
                kwargs=str(kwargs),
                exception=str(ex),
            ))
            raise ex

        else:
            log.info("Finished running job {job_name} with args: {args}, kwargs: {kwargs}.".format(
                job_name=cls.__name__,
                args=str(args),
                kwargs=str(kwargs),
            ))

    # ---

    __slots__ = [
        '_task',
    ]

    def __init__(self):
        """Constructor."""
        self._task = _CeleryTask(job_class=self.__class__)


class JobManager(object):
    """Celery job manager."""

    @classmethod
    def __result_for_task(cls, name: str, args: tuple, kwargs: dict) -> AsyncResult:
        app = JobBrokerApp(queue_name=name)
        result = app.send_task(name, args=args, kwargs=kwargs)
        return result

    @classmethod
    def run_remotely(cls, name: str, *args, **kwargs) -> Any:
        """Run job remotely, return the result."""
        result = cls.__result_for_task(name=name, args=args, kwargs=kwargs)
        return result.get()

    @classmethod
    def add_to_queue(cls, name: str, *args, **kwargs) -> str:
        """Add job to queue, return job ID."""
        result = cls.__result_for_task(name=name, args=args, kwargs=kwargs)
        return result.id


class McJobBrokerAppException(Exception):
    """JobBrokerApp() exception."""
    pass


class JobBrokerApp(celery.Celery):
    """Job broker class."""

    __slots__ = [
        '__job_class',
        '__task',
    ]

    def __init__(self, queue_name: str):
        """Return job broker (Celery app object) prepared for the specific queue name."""

        if not queue_name:
            raise McJobBrokerAppException("Queue name is empty.")

        config = CommonConfig()
        rabbitmq_config = config.rabbitmq()
        broker_uri = 'amqp://{username}:{password}@{hostname}:{port}/{vhost}'.format(
            username=rabbitmq_config.username(),
            password=rabbitmq_config.password(),
            hostname=rabbitmq_config.hostname(),
            port=rabbitmq_config.port(),
            vhost=rabbitmq_config.vhost(),
        )

        super().__init__(queue_name, broker=broker_uri)

        self.conf.broker_connection_timeout = rabbitmq_config.timeout()

        # Concurrency is done by us, not Celery itself
        self.conf.worker_concurrency = 1

        # Fetch only one job at a time
        self.conf.worker_prefetch_multiplier = 1

        self.conf.worker_max_tasks_per_child = 1000

        queue = Queue(
            name=queue_name,
            exchange=Exchange(queue_name),
            routing_key=queue_name,
            queue_arguments={
                'x-max-priority': 3,
                'x-queue-mode': 'lazy',
            },
        )
        self.conf.task_queues = [queue]

        # noinspection PyUnusedLocal
        def __route_task(name, args_, kwargs_, options_, task_=None, **kw_):
            return {
                'queue': name,
                'exchange': name,
                'routing_key': name,
            }

        self.conf.task_routes = (__route_task,)

    def start_worker(self):
        """Start worker for the job."""
        node_name = '{name}-{job_id}@{hostname}'.format(
            name=self.__job_class.__name__,
            job_id=uuid.uuid4(),
            hostname=socket.gethostname(),
        )
        log.info(f"Starting worker {node_name}...")
        self.worker_main(argv=[
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
