#!/usr/bin/env python3

from mediawords.annotator.nyt_labels_fetcher import NYTLabelsAnnotatorFetcher
from mediawords.db import connect_to_db
from mediawords.job import JobBroker
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class McNYTLabelsFetchAnnotationJobException(Exception):
    """NYTLabelsFetchAnnotationJob exception."""
    pass


def run_nytlabels_fetch_annotation(stories_id: int) -> None:
    """Fetch story's NYTLabels annotation."""
    if isinstance(stories_id, bytes):
        stories_id = decode_object_from_bytes_if_needed(stories_id)

    if stories_id is None:
        raise McNYTLabelsFetchAnnotationJobException("'stories_id' is None.")

    stories_id = int(stories_id)

    db = connect_to_db()

    log.info("Fetching annotation for story ID %d..." % stories_id)

    story = db.find_by_id(table='stories', object_id=stories_id)
    if story is None:
        raise McNYTLabelsFetchAnnotationJobException("Story with ID %d was not found." % stories_id)

    nytlabels = NYTLabelsAnnotatorFetcher()
    try:
        nytlabels.annotate_and_store_for_story(db=db, stories_id=stories_id)
    except Exception as ex:
        raise McNYTLabelsFetchAnnotationJobException(
            "Unable to process story $stories_id with NYTLabels: %s" % str(ex)
        )

    log.info("Adding story ID %d to the update story tags queue..." % stories_id)
    JobBroker(queue_name='MediaWords::Job::NYTLabels::UpdateStoryTags').add_to_queue(stories_id=stories_id)

    log.info("Finished fetching annotation for story ID %d" % stories_id)


if __name__ == '__main__':
    app = JobBroker(queue_name='MediaWords::Job::NYTLabels::FetchAnnotation')
    app.start_worker(handler=run_nytlabels_fetch_annotation)
