#!/usr/bin/env python3

from mediawords.db import connect_to_db
from mediawords.job import AbstractJob, McAbstractJobException, JobBrokerApp, JobManager
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

from mediawords.annotator.cliff_fetcher import CLIFFAnnotatorFetcher

log = create_logger(__name__)


class McCLIFFFetchAnnotationJobException(McAbstractJobException):
    """CLIFFFetchAnnotationJob exception."""
    pass


class CLIFFFetchAnnotationJob(AbstractJob):
    """

    Fetch story's CLIFF annotation.

    Start this worker script by running:

        ./script/run_in_env.sh ./mediacloud/mediawords/job/cliff/fetch_annotation.py

    """

    @classmethod
    def run_job(cls, stories_id: int) -> None:
        if isinstance(stories_id, bytes):
            stories_id = decode_object_from_bytes_if_needed(stories_id)

        if stories_id is None:
            raise McCLIFFFetchAnnotationJobException("'stories_id' is None.")

        stories_id = int(stories_id)

        db = connect_to_db()

        log.info("Fetching annotation for story ID %d..." % stories_id)

        story = db.find_by_id(table='stories', object_id=stories_id)
        if story is None:
            raise McCLIFFFetchAnnotationJobException("Story with ID %d was not found." % stories_id)

        cliff = CLIFFAnnotatorFetcher()
        try:
            cliff.annotate_and_store_for_story(db=db, stories_id=stories_id)
        except Exception as ex:
            raise McCLIFFFetchAnnotationJobException("Unable to process story $stories_id with CLIFF: %s" % str(ex))

        log.info("Adding story ID %d to the update story tags queue..." % stories_id)
        JobManager.add_to_queue(name='MediaWords::Job::CLIFF::UpdateStoryTags', stories_id=stories_id)

        log.info("Finished fetching annotation for story ID %d" % stories_id)

    @classmethod
    def queue_name(cls) -> str:
        return 'MediaWords::Job::CLIFF::FetchAnnotation'


if __name__ == '__main__':
    app = JobBrokerApp(queue_name=CLIFFFetchAnnotationJob.queue_name())
    app.start_worker()
