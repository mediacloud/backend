#!/usr/bin/env python3.5

from mediawords.annotator.nyt_labels import NYTLabelsAnnotator
from mediawords.db import connect_to_db
from mediawords.dbi.stories.processed import mark_as_processed
from mediawords.job import AbstractJob, McAbstractJobException, JobBrokerApp
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class McNYTLabelsUpdateStoryTagsJobException(McAbstractJobException):
    """NYTLabelsUpdateStoryTagsJob exception."""
    pass


class NYTLabelsUpdateStoryTagsJob(AbstractJob):
    """

    Create / update story tags using NYTLabels annotation

    Start this worker script by running:

        ./script/run_in_env.sh ./mediacloud/mediawords/job/nyt_labels/update_story_tags.py

    """

    @classmethod
    def run_job(cls, stories_id: int) -> None:
        if isinstance(stories_id, bytes):
            stories_id = decode_object_from_bytes_if_needed(stories_id)

        if stories_id is None:
            raise McNYTLabelsUpdateStoryTagsJobException("'stories_id' is None.")

        stories_id = int(stories_id)

        db = connect_to_db()

        log.info("Updating tags for story ID %d..." % stories_id)

        story = db.find_by_id(table='stories', object_id=stories_id)
        if story is None:
            raise McNYTLabelsUpdateStoryTagsJobException("Story with ID %d was not found." % stories_id)

        nytlabels = NYTLabelsAnnotator()
        try:
            nytlabels.update_tags_for_story(db=db, stories_id=stories_id)
        except Exception as ex:
            raise McNYTLabelsUpdateStoryTagsJobException(
                "Unable to process story ID %d with NYTLabels: %s" % (stories_id, str(ex),)
            )

        log.info("Marking story ID %d as processed..." % stories_id)
        mark_as_processed(db=db, stories_id=stories_id)

        log.info("Finished updating tags for story ID %d" % stories_id)

    @classmethod
    def queue_name(cls) -> str:
        return 'MediaWords::Job::NYTLabels::UpdateStoryTags'


if __name__ == '__main__':
    app = JobBrokerApp(job_class=NYTLabelsUpdateStoryTagsJob)
    app.start_worker()
