import abc
from collections import Iterator
from typing import List

from mediawords.db import DatabaseHandler
from mediawords.languages.factory import LanguageFactory
from mediawords.util.identify_language import identification_would_be_reliable, language_code_for_text
from mediawords.util.log import create_logger
from mediawords.util.word2vec import McWord2vecException

log = create_logger(__name__)


class AbstractSentenceIterator(Iterator, metaclass=abc.ABCMeta):
    """Abstract story sentence iterator."""
    pass


class SnapshotSentenceIterator(AbstractSentenceIterator, metaclass=abc.ABCMeta):
    """Iterator that iterates over sentences in a snapshot."""

    def __init__(self, db: DatabaseHandler, snapshots_id: int):
        super().__init__()

        snapshots_id = int(snapshots_id)

        # Verify that topic exists
        if db.find_by_id(table='snapshots', object_id=snapshots_id) is None:
            raise McWord2vecException("Snapshot with ID %d does not exist." % snapshots_id)

        self.__snapshots_id = snapshots_id

        self.__sentence_counter = 0

        log.info("Creating COPY TO object...")
        self.__copy_to = db.copy_to("""
            COPY (
                SELECT story_sentences.sentence
                FROM snap.stories
                    INNER JOIN story_sentences
                        ON snap.stories.stories_id = story_sentences.stories_id
                WHERE snap.stories.snapshots_id = %d
            ) TO STDOUT WITH CSV
        """ % snapshots_id)

    def __next__(self) -> List[str]:
        """Return list of next sentence's words to be added to the word2vec vector."""

        if self.__copy_to is None:
            raise StopIteration

        sentence = self.__copy_to.get_line()

        if sentence is None:
            self.__copy_to.end()
            self.__copy_to = None
            raise StopIteration

        sentence = sentence.strip()

        self.__sentence_counter += 1
        if self.__sentence_counter % 1000 == 0:
            log.info("Feeding sentence %d..." % self.__sentence_counter)

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
