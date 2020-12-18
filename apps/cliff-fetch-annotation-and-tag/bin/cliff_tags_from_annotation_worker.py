#!/usr/bin/env python3

from cliff_fetch_annotation_and_tag.cliff_tags_from_annotation import CLIFFTagsFromAnnotation
from mediawords.db import connect_to_db
from mediawords.job import JobBroker
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class McCLIFFTagsFromAnnotationJobException(Exception):
    """CLIFFTagsFromAnnotationJob exception."""
    pass


def run_cliff_tags_from_annotation(stories_id: int) -> None:
    """Fetch story's CLIFF annotation and uses it to generate/store tags"""
    if isinstance(stories_id, bytes):
        stories_id = decode_object_from_bytes_if_needed(stories_id)

    if stories_id is None:
        raise McCLIFFTagsFromAnnotationJobException("'stories_id' is None.")

    stories_id = int(stories_id)

    db = connect_to_db()

    log.info("Updating tags for story ID %d..." % stories_id)

    story = db.find_by_id(table='stories', object_id=stories_id)
    if story is None:
        raise McCLIFFTagsFromAnnotationJobException("Story with ID %d was not found." % stories_id)

    cliff = CLIFFTagsFromAnnotation()
    try:
        cliff.update_tags_for_story(db=db, stories_id=stories_id)
    except Exception as ex:
        raise McCLIFFTagsFromAnnotationJobException(
            "Unable to process story ID %s with CLIFF: %s" % (stories_id, str(ex),)
        )

    log.info("Adding story ID %d to NYTLabels fetch queue..." % stories_id)
    JobBroker(queue_name='MediaWords::Job::NYTLabels::FetchAnnotationAndTag').add_to_queue(stories_id=stories_id)

    log.info("Finished updating tags for story ID %d" % stories_id)


if __name__ == '__main__':
    app = JobBroker(queue_name='MediaWords::Job::CLIFF::FetchAnnotationAndTag')
    app.start_worker(handler=run_cliff_tags_from_annotation)
