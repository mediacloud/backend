#!/usr/bin/env python3

"""Topic Mapper job that extracts links from a single story and inserts them into topic_links."""

import traceback

from mediawords.db import connect_to_db
from mediawords.job import AbstractJob, McAbstractJobException, JobBrokerApp
import mediawords.tm.extract_story_links
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class McExtractStoryLinksJobException(McAbstractJobException):
    """Exceptions dealing with job setup and routing."""

    pass


class ExtractStoryLinksJob(AbstractJob):
    """
    Extract links from a story for a topic and insert the resulting links into topic_links.

    Start this worker script by running:

        ./script/run_in_env.sh ./mediacloud/mediawords/job/tm/extract_story_links.py
    """

    @classmethod
    def run_job(cls, stories_id: int, topics_id: int) -> None:
        """Run the extract_story_links job, using mediawords.tm.extract_story_links for the logic."""
        if isinstance(stories_id, bytes):
            stories_id = decode_object_from_bytes_if_needed(stories_id)
        if stories_id is None:
            raise McExtractStoryLinksJobException("'stories_id' is None.")

        if isinstance(topics_id, bytes):
            topics_id = decode_object_from_bytes_if_needed(topics_id)
        if topics_id is None:
            raise McExtractStoryLinksJobException("'topics_id' is None.")

        stories_id = int(stories_id)
        topics_id = int(topics_id)

        log.info("Start fetching extracting links for stories_id %d topics_id %d" % (stories_id, topics_id))

        try:
            db = connect_to_db()
            story = db.require_by_id(table='stories', object_id=stories_id)
            topic = db.require_by_id(table='topics', object_id=topics_id)
            mediawords.tm.extract_story_links.extract_links_for_topic_story(db, story, topic)

        except Exception as ex:
            log.error("Error while processing story {}: {}".format(stories_id, ex))
            raise McExtractStoryLinksJobException(
                "Unable to process story {}: {}".format(stories_id, traceback.format_exc())
            )

        log.info("Finished fetching extracting links for stories_id %d topics_id %d" % (stories_id, topics_id))

    @classmethod
    def queue_name(cls) -> str:
        """Set queue name."""
        return 'MediaWords::Job::TM::ExtractStoryLinks'


if __name__ == '__main__':
    app = JobBrokerApp(job_class=ExtractStoryLinksJob)
    app.start_worker()
