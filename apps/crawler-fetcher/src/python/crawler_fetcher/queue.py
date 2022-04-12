"""
The ONE place that knows the format of a queue entry for feed_parse_worker
"""

# there isn't currently a default queue name, but if there was,
# this seems like the place to declare it!

from mediawords.job import JobBroker

# XXX maybe take downloads dict?
def queue_to_feed_parse_worker(queue: str, downloads_id: int):
    """
    queue feed download to a feed_download_worker
    (may run multiple queues/worker pools for different work loads)
    """

    # kw args to add_to_queue are passed to feed_parse_worker
    # XXX want to be able to pass create_task_missing_queues=False to Celery!
    JobBroker(queue_name=queue).add_to_queue(downloads_id=downloads_id)
