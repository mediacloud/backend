import os
import subprocess
import time

from mediawords.job import JobBroker
from mediawords.util.log import create_logger

log = create_logger(__name__)


def test_worker_fatal_error():
    worker_path = '/opt/mediacloud/tests/python/mediawords/job/failing_worker.py'
    assert os.path.isfile(worker_path), f"Worker '{worker_path}' exists."
    assert os.access(worker_path, os.X_OK), f"Worker '{worker_path}' is executable."

    worker_process = subprocess.Popen([worker_path])
    assert worker_process.poll() is None, "Worker process is still running."

    JobBroker(queue_name='MediaWords::Job::FailingWorker').add_to_queue()

    return_code = None
    for retry in range(10):
        log.info(f"Waiting for the process to stop (retry {retry})...")
        return_code = worker_process.poll()
        if return_code is not None:
            log.info(f"Process stopped with return code {return_code}")
            break
        time.sleep(1)

    assert return_code is not None, "Process has managed to stop."
    assert return_code != 0, f"Process returned non-zero exit code {return_code}."
