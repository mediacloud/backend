import abc
from abc import ABC
from collections import deque
from collections.abc import Iterator
from typing import List, Optional

from mediawords.db import DatabaseHandler
from mediawords.languages.factory import LanguageFactory
from mediawords.util.identify_language import identification_would_be_reliable, language_code_for_text
from mediawords.util.log import create_logger
from word2vec_generate_snapshot_model import McWord2vecException

log = create_logger(__name__)


class AbstractSentenceIterator(Iterator, ABC, metaclass=abc.ABCMeta):
    """Abstract story sentence iterator."""
    pass


class SnapshotSentenceIterator(AbstractSentenceIterator, metaclass=abc.ABCMeta):
    """Iterator that iterates over sentences in a snapshot."""

    __DEFAULT_STORIES_ID_CHUNK_SIZE = 1000

    __slots__ = [
        '__db',
        '__snapshots_id',

        # Deque of sentences
        '__sentences_deque',

        # How many stories (and their sentences) to fetch in a single chunk
        '__stories_id_chunk_size',

        # Last "stories_id" of the last fetched story ID chunk
        '__last_encountered_stories_id',
    ]

    def __init__(self,
                 db: DatabaseHandler,
                 snapshots_id: int,
                 stories_id_chunk_size: int = __DEFAULT_STORIES_ID_CHUNK_SIZE):
        super().__init__()

        snapshots_id = int(snapshots_id)

        self.__db = db
        self.__snapshots_id = snapshots_id
        self.__stories_id_chunk_size = stories_id_chunk_size

        self.__sentences_deque = deque()
        self.__last_encountered_stories_id = 0

        # Verify that the snapshot exists
        if db.find_by_id(table='snapshots', object_id=snapshots_id) is None:
            raise McWord2vecException("Snapshot with ID %d does not exist." % snapshots_id)

    def __fetch_next_sentences_chunk(self) -> List[str]:
        """Fetch next chunk of story sentences of the current stories_id offset; might return an empty list.

        When a snapshot has many (300k+) stories, SELECTs from story_sentences with WHERE or INNER JOIN to snap.stories
        all lead to sequential scans which take forever. To prevent that, we fetch sentences for up to
        "stories_id_chunk_size" stories at a time, feed them in __next__(), and then fetch another chunk.
        """

        chunk = self.__db.query("""
            SELECT stories_id, sentence
            FROM story_sentences
            WHERE stories_id IN (
                SELECT stories_id
                FROM snap.stories
                WHERE snapshots_id = %(snapshots_id)s

                  -- Reasonably fast, but maybe OFFSET would be even faster?
                  AND stories_id > %(last_encountered_stories_id)s
                ORDER BY stories_id
                LIMIT %(stories_id_chunk_size)s
            )

            -- Need ORDER to write down last fetched "stories_id"
            ORDER BY stories_id, sentence_number
        """, {
            'snapshots_id': self.__snapshots_id,
            'last_encountered_stories_id': self.__last_encountered_stories_id,
            'stories_id_chunk_size': self.__stories_id_chunk_size,
        }).hashes()

        if len(chunk):
            self.__last_encountered_stories_id = chunk[-1]['stories_id']

        sentences = [x['sentence'] for x in chunk]

        return sentences

    def __next_sentence(self) -> Optional[str]:
        """(Fetch if needed and) return next sentence; return None if no more sentences are to be found."""

        if len(self.__sentences_deque) == 0:

            log.info("Fetching sentences with stories_id offset {} for up to {} stories...".format(
                self.__last_encountered_stories_id,
                self.__stories_id_chunk_size,
            ))
            chunk = self.__fetch_next_sentences_chunk()
            self.__sentences_deque.extend(chunk)

            log.info("Fetched {} sentences".format(len(chunk)))

            # Still empty after a fetch?
            if len(self.__sentences_deque) == 0:
                return None

        return self.__sentences_deque.popleft()

    def __next__(self) -> List[str]:
        """Return list of next sentence's words to be added to the word2vec vector."""

        sentence = self.__next_sentence()
        if sentence is None:
            raise StopIteration

        sentence = sentence.strip()

        if not len(sentence):
            return []

        language = None
        if identification_would_be_reliable(sentence):
            language_code = language_code_for_text(sentence)
            language = LanguageFactory.language_for_code(language_code)
        if language is None:
            language = LanguageFactory.default_language()

        words = language.split_sentence_to_words(sentence)

        if not len(words):
            return []

        return words
