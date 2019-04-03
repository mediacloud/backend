from mediawords.db import DatabaseHandler
from mediawords.dbi.downloads.extract import extract_and_create_download_text
from mediawords.dbi.stories.extractor_arguments import PyExtractorArguments
from mediawords.dbi.stories.process import process_extracted_story
from mediawords.util.log import create_logger
from mediawords.util.parse_html import html_strip
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


def __get_full_text_from_rss(story: dict) -> str:
    story = decode_object_from_bytes_if_needed(story)

    story_title = story.get('title', '')
    story_description = story.get('description', '')

    return "\n\n".join([html_strip(story_title), html_strip(story_description)])


def _get_extracted_text(db: DatabaseHandler, story: dict) -> str:
    """Return the concatenated download_texts associated with the story."""

    story = decode_object_from_bytes_if_needed(story)

    # "download_texts" INT -> BIGINT join hack: convert parameter downloads_id to a constant array first
    download_texts = db.query("""
        SELECT download_text
        FROM download_texts
        WHERE downloads_id = ANY(
            ARRAY(
                SELECT downloads_id
                FROM downloads
                WHERE stories_id = %(stories_id)s
            )
        )
        ORDER BY downloads_id
    """, {'stories_id': story['stories_id']}).flat()

    return ".\n\n".join(download_texts)


def get_text_for_word_counts(db: DatabaseHandler, story: dict) -> str:
    """Get story title + description + body concatenated into a single string.

    This is what is used to fetch text to generate story_sentences, which eventually get imported into Solr.

    If the text of the story ends up being shorter than the description, return the title + description instead of the
    story text (some times the extractor falls down and we end up with better data just using the title + description.
    """
    story = decode_object_from_bytes_if_needed(story)

    if story['full_text_rss']:
        story_text = __get_full_text_from_rss(story)
    else:
        story_text = _get_extracted_text(db=db, story=story)

    story_description = story.get('description', '')

    if story_text is None:
        story_text = ''
    if story_description is None:
        story_description = ''

    if len(story_text) == 0 or len(story_text) < len(story_description):
        story_text = html_strip(story['title']).strip()

        if story_description:
            story_text += "\n\n"
            story_text += html_strip(story_description).strip()

    return story_text


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
