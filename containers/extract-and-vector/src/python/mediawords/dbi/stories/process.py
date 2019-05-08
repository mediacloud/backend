from mediawords.db import DatabaseHandler
from mediawords.dbi.stories.extractor_arguments import PyExtractorArguments
from mediawords.dbi.stories.postprocess import mark_as_processed, story_is_english_and_has_sentences
from mediawords.job import JobBroker
from mediawords.story_vectors import update_story_sentences_and_language
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class McProcessExtractedStoryException(Exception):
    """process_extracted_story() exception."""
    pass


def process_extracted_story(db: DatabaseHandler, story: dict, extractor_args: PyExtractorArguments) -> None:
    """Do post extraction story processing work by calling update_story_sentences_and_language()."""
    story = decode_object_from_bytes_if_needed(story)

    stories_id = story['stories_id']

    log.debug("Updating sentences and language for story {}...".format(stories_id))
    update_story_sentences_and_language(db=db, story=story, extractor_args=extractor_args)

    # Extract -> CLIFF -> NYTLabels -> mark_as_processed() chain
    if story_is_english_and_has_sentences(db=db, stories_id=stories_id):
        # If CLIFF annotator is enabled, cliff/update_story_tags job will check whether NYTLabels annotator is enabled,
        # and if it is, will pass the story further to NYTLabels. NYTLabels, in turn, will mark the story as processed.
        log.debug("Adding story {} to CLIFF annotation queue...".format(stories_id))
        JobBroker(queue_name='MediaWords::Job::CLIFF::FetchAnnotation').add_to_queue(stories_id=stories_id)

    else:
        log.debug("Won't add {} to CLIFF annotation queue because it's not annotatable with CLIFF".format(stories_id))

        if story_is_english_and_has_sentences(db=db, stories_id=stories_id):
            # If CLIFF annotator is disabled, pass the story to NYTLabels annotator which, if run, will mark the story
            # as processed
            log.debug("Adding story {} to NYTLabels annotation queue...".format(stories_id))
            JobBroker(queue_name='MediaWords::Job::NYTLabels::FetchAnnotation').add_to_queue(stories_id=stories_id)

        else:
            log.debug("Won't add {} to NYTLabels annotation queue because it's not annotatable with NYTLabels".format(
                stories_id
            ))

            # If neither of the annotators are enabled, mark the story as processed ourselves
            log.debug("Marking the story as processed...")
            if not mark_as_processed(db=db, stories_id=stories_id):
                raise McProcessExtractedStoryException("Unable to mark story ID {} as processed".format(stories_id))
