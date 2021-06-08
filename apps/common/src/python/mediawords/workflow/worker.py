import asyncio

from temporal.worker import Worker


async def stop_worker_faster(worker: Worker) -> None:
    """
    Stops worker but does it slightly faster.

    Default implementation of worker.stop() sleeps for 5 seconds between retries. We sleep a bit less.

    :param worker: Worker instance to stop
    """
    worker.stop_requested = True
    while worker.threads_stopped != worker.threads_started:
        await asyncio.sleep(0.5)
