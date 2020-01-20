from mediawords.db import DatabaseHandler
from mediawords.dbi.downloads import create_download_for_new_story

from podcast_fetch_transcript.fetch import Transcript


def download_text_from_transcript(transcript: Transcript) -> str:
    best_utterance_alternatives = []
    for utterance in transcript.utterances:
        best_utterance_alternatives.append(utterance.best_alternative.text)
    text = "\n".join(best_utterance_alternatives)
    return text


def store_transcript(db: DatabaseHandler, stories_id: int, transcript: Transcript) -> None:
    story = db.find_by_id(table='stories', object_id=stories_id)

    feed = db.query("""
        SELECT *
        FROM feeds
        WHERE feeds_id = (
            SELECT feeds_id
            FROM feeds_stories_map
            WHERE stories_id = %(stories_id)s
        )
    """, {
        'stories_id': stories_id,
    }).hash()

    download = create_download_for_new_story(db=db, story=story, feed=feed)

    text = download_text_from_transcript(transcript=transcript)

    db.insert(table='download_texts', insert_hash={
        'downloads_id': download['downloads_id'],
        'download_text': text,
        'download_text_length': len(text),
    })
