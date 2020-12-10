#!/usr/bin/env python3

from mediawords.db import connect_to_db
from mediawords.dbi.stories.postprocess import mark_as_processed
from mediawords.job import JobBroker
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from nytlabels_fetch_annotation_and_tag.nytlabels_tags_from_annotation import NYTLabelsTagsFromAnnotation

log = create_logger(__name__)


class McNYTLabelsTagsFromAnnotationJobException(Exception):
    """NYTLabelsTagsFromAnnotationJob exception."""
    pass


def run_nytlabels_tags_from_annotation(stories_id: int) -> None:
    """Fetches a story's NYT Labels annotation and uses it to generate/store tags"""
    if isinstance(stories_id, bytes):
        stories_id = decode_object_from_bytes_if_needed(stories_id)

    if stories_id is None:
        raise McNYTLabelsTagsFromAnnotationJobException("'stories_id' is None.")

    stories_id = int(stories_id)

    db = connect_to_db()

    log.info("Updating tags for story ID %d..." % stories_id)

    story = db.find_by_id(table='stories', object_id=stories_id)
    if story is None:
        raise McNYTLabelsTagsFromAnnotationJobException("Story with ID %d was not found." % stories_id)

    nytlabels = NYTLabelsTagsFromAnnotation()
    try:
        nytlabels.update_tags_for_story(db=db, stories_id=stories_id)
    except Exception as ex:
        raise McNYTLabelsTagsFromAnnotationJobException(
            "Unable to process story ID %d with NYTLabels: %s" % (stories_id, str(ex),)
        )

    log.info("Marking story ID %d as processed..." % stories_id)
    mark_as_processed(db=db, stories_id=stories_id)

    log.info("Finished updating tags for story ID %d" % stories_id)


if __name__ == '__main__':
    app = JobBroker(queue_name='MediaWords::Job::NYTLabels::TagsFromAnnotation')
    app.start_worker(handler=run_nytlabels_tags_from_annotation)
