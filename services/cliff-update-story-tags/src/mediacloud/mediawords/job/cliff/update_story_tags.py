#!/usr/bin/env python3

from mediawords.annotator.cliff import CLIFFAnnotator
from mediawords.db import connect_to_db
from mediawords.job import AbstractJob, McAbstractJobException, JobBrokerApp
from mediawords.job.nyt_labels.fetch_annotation import NYTLabelsFetchAnnotationJob
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class McCLIFFUpdateStoryTagsJobException(McAbstractJobException):
    """CLIFFUpdateStoryTagsJob exception."""
    pass


class CLIFFUpdateStoryTagsJob(AbstractJob):
    """

    Create / update story tags using CLIFF annotation

    Start this worker script by running:

        ./script/run_in_env.sh ./mediacloud/mediawords/job/cliff/update_story_tags.py

    """

    @classmethod
    def run_job(cls, stories_id: int) -> None:
        if isinstance(stories_id, bytes):
            stories_id = decode_object_from_bytes_if_needed(stories_id)

        if stories_id is None:
            raise McCLIFFUpdateStoryTagsJobException("'stories_id' is None.")

        stories_id = int(stories_id)

        db = connect_to_db()

        log.info("Updating tags for story ID %d..." % stories_id)

        story = db.find_by_id(table='stories', object_id=stories_id)
        if story is None:
            raise McCLIFFUpdateStoryTagsJobException("Story with ID %d was not found." % stories_id)

        cliff = CLIFFAnnotator()
        try:
            cliff.update_tags_for_story(db=db, stories_id=stories_id)
        except Exception as ex:
            raise McCLIFFUpdateStoryTagsJobException(
                "Unable to process story ID %s with CLIFF: %s" % (stories_id, str(ex),)
            )

        log.info("Adding story ID %d to NYTLabels fetch queue..." % stories_id)
        NYTLabelsFetchAnnotationJob.add_to_queue(stories_id=stories_id)

        log.info("Finished updating tags for story ID %d" % stories_id)

    @classmethod
    def queue_name(cls) -> str:
        return 'MediaWords::Job::CLIFF::UpdateStoryTags'


if __name__ == '__main__':
    app = JobBrokerApp(job_class=CLIFFUpdateStoryTagsJob)
    app.start_worker()
