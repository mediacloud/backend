#!/usr/bin/env python3

from mediawords.job import JobBroker
from mediawords.util.log import create_logger
from topics_mine.mine import run_worker_job

log = create_logger(__name__)

QUEUE_NAME = 'MediaWords::Job::TM::MineTopic'

if __name__ == '__main__':
    app = JobBroker(queue_name=QUEUE_NAME)
    app.start_worker(handler=run_worker_job)
