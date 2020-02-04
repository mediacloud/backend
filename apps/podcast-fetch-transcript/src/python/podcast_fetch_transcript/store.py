from mediawords.db import DatabaseHandler
from mediawords.dbi.downloads import create_download_for_new_story
from mediawords.dbi.downloads.store import store_content

from podcast_fetch_transcript.fetch import Transcript


def download_text_from_transcript(transcript: Transcript) -> str:
    best_utterance_alternatives = []
    for utterance in transcript.utterances:
        best_utterance_alternatives.append(utterance.best_alternative.text)
    text = "\n\n".join(best_utterance_alternatives)
    return text


def store_transcript(db: DatabaseHandler, transcript: Transcript) -> int:
    """
    Store transcript to raw download store.

    We could write this directly to "download_texts", but if we decide to reextract everything (after, say, updating an
    extractor), that "download_texts" row might disappear, so it's safer to just store a raw download on the key-value
    store as if it was a HTML file or something.

    :param db: Database handler.
    :param transcript: Transcript object.
    :return: Download ID for a download that was created.
    """
    story = db.find_by_id(table='stories', object_id=transcript.stories_id)

    feed = db.query("""
        SELECT *
        FROM feeds
        WHERE feeds_id = (
            SELECT feeds_id
            FROM feeds_stories_map
            WHERE stories_id = %(stories_id)s
        )
    """, {
        'stories_id': transcript.stories_id,
    }).hash()

    download = create_download_for_new_story(db=db, story=story, feed=feed)

    text = download_text_from_transcript(transcript=transcript)

    # Store as a raw download and then let "extract-and-vector" app "extract" the stored text later
    store_content(db=db, download=download, content=text)

    return download['downloads_id']
