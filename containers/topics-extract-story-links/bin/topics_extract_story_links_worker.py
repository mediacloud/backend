#!/usr/bin/env python3

"""Topic Mapper job that extracts links from a single story and inserts them into topic_links."""

import traceback

from mediawords.db import connect_to_db
from mediawords.job import JobBroker
from mediawords.tm.extract_story_links import extract_links_for_topic_story
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class McExtractStoryLinksJobException(Exception):
    """Exceptions dealing with job setup and routing."""
    pass


def run_topics_extract_story_links(stories_id: int, topics_id: int) -> None:
    """Extract links from a story for a topic and insert the resulting links into topic_links."""
    if isinstance(stories_id, bytes):
        stories_id = decode_object_from_bytes_if_needed(stories_id)
    stories_id = int(stories_id)

    if stories_id is None:
        raise McExtractStoryLinksJobException("'stories_id' is None.")

    if isinstance(topics_id, bytes):
        topics_id = decode_object_from_bytes_if_needed(topics_id)
    topics_id = int(topics_id)

    if topics_id is None:
        raise McExtractStoryLinksJobException("'topics_id' is None.")

    stories_id = int(stories_id)
    topics_id = int(topics_id)

    db = connect_to_db()

    log.info("Start fetching extracting links for stories_id %d topics_id %d" % (stories_id, topics_id))

    try:
        extract_links_for_topic_story(db=db, stories_id=stories_id, topics_id=topics_id)

    except Exception as ex:
        log.error("Error while processing story {}: {}".format(stories_id, ex))
        raise McExtractStoryLinksJobException(
            "Unable to process story {}: {}".format(stories_id, traceback.format_exc())
        )

    log.info("Finished fetching extracting links for stories_id %d topics_id %d" % (stories_id, topics_id))


if __name__ == '__main__':
    app = JobBroker(queue_name='MediaWords::Job::TM::ExtractStoryLinks')
    app.start_worker(handler=run_topics_extract_story_links)
