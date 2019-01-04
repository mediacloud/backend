from mediawords.db import DatabaseHandler
from mediawords.util.parse_html import html_strip
from mediawords.util.perl import decode_object_from_bytes_if_needed


def __get_full_text_from_rss(story: dict) -> str:
    story = decode_object_from_bytes_if_needed(story)

    story_title = story.get('title', '')
    story_description = story.get('description', '')

    return "\n\n".join([html_strip(story_title), html_strip(story_description)])


def _get_extracted_text(db: DatabaseHandler, story: dict) -> str:
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

            if not story_text.endswith('.'):
                story_text += '.'

            story_text += "\n\n"
            story_text += html_strip(story_description).strip()

    return story_text
