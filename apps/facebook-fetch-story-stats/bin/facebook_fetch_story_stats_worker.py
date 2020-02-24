#!/usr/bin/env python3

"""
Fetch story's share count statistics via Facebook's Graph API.
"""

from mediawords.db import connect_to_db
from mediawords.job import JobBroker
from mediawords.util.log import create_logger
from mediawords.util.process import fatal_error

from facebook_fetch_story_stats import FacebookConfig, get_and_store_story_stats
from facebook_fetch_story_stats.exceptions import McFacebookSoftFailureException, McFacebookHardFailureException

log = create_logger(__name__)


def run_facebook_fetch_story_stats(stories_id: int) -> None:
    """Fetch Facebook stats for a story in the job queue; throw exception on soft errors, sys.exit(1) on hard errors."""

    if not stories_id:
        fatal_error("'stories_id' is not set.")

    stories_id = int(stories_id)

    if not FacebookConfig.is_enabled():
        fatal_error("Facebook API processing is not enabled.")

    db = None
    try:
        db = connect_to_db()
    except Exception as ex:
        # On connection errors, we actually want to die and wait to be (auto)restarted because otherwise we will
        # continue on fetching new jobs from RabbitMQ and failing all of them
        fatal_error(f"Unable to connect to PostgreSQL: {ex}")

    story = db.find_by_id(table='stories', object_id=stories_id)
    if not story:
        # If one or more stories don't exist, that's okay and we can just fail this job
        raise Exception(f"Story with ID {stories_id} does not exist.")

    log.info(f"Fetching story stats for story {stories_id}...")

    try:
        get_and_store_story_stats(db=db, story=story)

    except McFacebookSoftFailureException as ex:
        # On soft errors, just raise the exception further as we have reason to believe that the request will succeed on
        # other stories in the job queue
        log.error(f"Error while fetching stats for story {stories_id}: {ex}")
        raise ex

    except McFacebookHardFailureException as ex:
        # On hard errors, stop the whole worker as we most likely can't continue without a developer having a look into
        # what's happening
        fatal_error(f"Fatal error while fetching stats for story {stories_id}: {ex}")

    except Exception as ex:
        # On unknown exceptions, also go for sys.exit(1) as we don't really know what happened as they shouldn't be
        # thrown anyway
        fatal_error(f"Unknown exception while fetching stats for story {stories_id}: {ex}")

    log.info(f"Done fetching story stats for story {stories_id}.")


if __name__ == '__main__':
    app = JobBroker(queue_name='MediaWords::Job::Facebook::FetchStoryStats')
    app.start_worker(handler=run_facebook_fetch_story_stats)
