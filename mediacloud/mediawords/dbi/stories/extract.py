from typing import Optional, List

from mediawords.db import DatabaseHandler
from mediawords.util.html import html_strip
from mediawords.util.perl import decode_object_from_bytes_if_needed


def combine_story_title_description_text(story_title: Optional[str],
                                         story_description: Optional[str],
                                         download_texts: List[str]) -> str:
    """Get the combined story title, story description, and download text of the story in a consistent way."""
    story_title = decode_object_from_bytes_if_needed(story_title)
    story_description = decode_object_from_bytes_if_needed(story_description)
    download_texts = decode_object_from_bytes_if_needed(download_texts)

    if story_title is None:
        story_title = ''

    if story_description is None:
        story_description = ''

    return "\n***\n\n".join([html_strip(story_title), html_strip(story_description)] + download_texts)


def __get_full_text_from_rss(story: dict) -> str:
    story = decode_object_from_bytes_if_needed(story)

    story_title = story.get('title', '')
    story_description = story.get('description', '')

    return "\n\n".join([html_strip(story_title), html_strip(story_description)])


def get_extracted_text(db: DatabaseHandler, story: dict) -> str:
    """Return the concatenated download_texts associated with the story."""

    story = decode_object_from_bytes_if_needed(story)

    download_texts = db.query("""
        SELECT dt.download_text
        FROM downloads AS d,
             download_texts AS dt
        WHERE dt.downloads_id = d.downloads_id
          AND d.stories_id = %(stories_id)s
        ORDER BY d.downloads_id
    """, {'stories_id': story['stories_id']}).flat()

    return ".\n\n".join(download_texts)


def get_text_for_word_counts(db: DatabaseHandler, story: dict) -> str:
    """Like get_text(), but it doesn't include both title + description and the extracted text.

    This is what is used to fetch text to generate story_sentences, which eventually get imported into Solr.

    If the text of the story ends up being shorter than the description, return the title + description instead of the
    story text (some times the extractor falls down and we end up with better data just using the title + description.
    """
    story = decode_object_from_bytes_if_needed(story)

    if story['full_text_rss']:
        story_text = __get_full_text_from_rss(story)
    else:
        story_text = get_extracted_text(db=db, story=story)

    story_description = story.get('description', '')

    if story_text is None:
        story_text = ''
    if story_description is None:
        story_description = ''

    if len(story_text) == 0 or len(story_text) < len(story_description):
        story_text = html_strip(story['title'])
        if story['description']:

            story_text = story_text.strip()
            if not story_text.endswith('.'):
                story_text += '.'

            story_text += html_strip(story['description'])

    return story_text


def get_text(db: DatabaseHandler, story: dict) -> str:
    """Get the concatenation of the story title and description and all of the download_texts associated with the story
    in a consistent way.

    If full_text_rss is True for the medium, just return the concatenation of the story title and description.
    """

    story = decode_object_from_bytes_if_needed(story)

    if story['full_text_rss']:
        return __get_full_text_from_rss(story=story)

    download_texts = db.query("""
        SELECT download_text
        FROM download_texts AS dt,
             downloads AS d
        WHERE d.downloads_id = dt.downloads_id
          AND d.stories_id = %(stories_id)s
        ORDER BY d.downloads_id ASC
    """, {'stories_id': story['stories_id']}).flat()

    pending_downloads = db.query("""
        SELECT downloads_id
        FROM downloads
        WHERE extracted = 'f'
          AND stories_id = %(stories_id)s
          AND type = 'content'
    """, {'stories_id': story['stories_id']}).hashes()

    if pending_downloads is not None and len(pending_downloads) > 0:
        download_texts.append("(downloads pending extraction)")

    story_text = combine_story_title_description_text(
        story_title=story['title'],
        story_description=story['description'],
        download_texts=download_texts,
    )

    return story_text
