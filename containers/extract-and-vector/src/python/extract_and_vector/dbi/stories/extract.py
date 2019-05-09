from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
from extract_and_vector.dbi.stories.extractor_arguments import PyExtractorArguments
from extract_and_vector.dbi.downloads.extract import extract_and_create_download_text
from extract_and_vector.dbi.stories.process import process_extracted_story

log = create_logger(__name__)


def extract_and_process_story(db: DatabaseHandler,
                              story: dict,
                              extractor_args: PyExtractorArguments = PyExtractorArguments()) -> None:
    """Extract all of the downloads for the given story and then call process_extracted_story()."""

    story = decode_object_from_bytes_if_needed(story)

    stories_id = story['stories_id']

    use_transaction = not db.in_transaction()
    if use_transaction:
        db.begin()

    log.debug("Fetching downloads for story {}...".format(stories_id))
    downloads = db.query("""
        SELECT *
        FROM downloads
        WHERE stories_id = %(stories_id)s
          AND type = 'content'
        ORDER BY downloads_id ASC
    """, {'stories_id': stories_id}).hashes()

    # MC_REWRITE_TO_PYTHON: Perlism
    if downloads is None:
        downloads = []

    for download in downloads:
        log.debug("Extracting download {} for story {}...".format(download['downloads_id'], stories_id))
        extract_and_create_download_text(db=db, download=download, extractor_args=extractor_args)

    log.debug("Processing extracted story {}...".format(stories_id))
    process_extracted_story(db=db, story=story, extractor_args=extractor_args)

    if use_transaction:
        db.commit()
