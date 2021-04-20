from mediawords.db import DatabaseHandler
from mediawords.dbi.downloads import create_download_for_new_story
from mediawords.dbi.downloads.store import store_content
from mediawords.util.log import create_logger

from src.python.podcast_transcribe_episode.fetch_episode.transcript import Transcript

log = create_logger(__name__)


class DefaultHandler(AbstractHandler):

    @classmethod
    def _download_text_from_transcript(cls, transcript: Transcript) -> str:
        best_utterance_alternatives = []
        for utterance in transcript.utterances:
            best_utterance_alternatives.append(utterance.best_alternative.text)
        text = "\n\n".join(best_utterance_alternatives)
        return text

    @classmethod
    def store_transcript(cls, db: DatabaseHandler, transcript: Transcript) -> int:
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

        text = cls._download_text_from_transcript(transcript=transcript)

        # Store as a raw download and then let "extract-and-vector" app "extract" the stored text later
        store_content(db=db, download=download, content=text)

        return download['downloads_id']
