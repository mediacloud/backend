import abc
from abc import ABC
from collections.abc import Iterator
from typing import List

from mediawords.db import DatabaseHandler
from mediawords.languages.factory import LanguageFactory
from mediawords.util.identify_language import identification_would_be_reliable, language_code_for_text
from mediawords.util.log import create_logger
from mediawords.util.text import random_string
from mediawords.util.word2vec import McWord2vecException

log = create_logger(__name__)


class AbstractSentenceIterator(Iterator, ABC, metaclass=abc.ABCMeta):
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

        # Subselect such as:
        #
        #     SELECT sentence
        #     FROM story_sentences
        #     WHERE stories_id IN (
        #         SELECT stories_id
        #         FROM snap.snapshots
        #         WHERE snapshots_id = ...
        #     )
        #
        # or its variants (e.g. INNER JOIN) makes the query planner decide on a sequential scan on "story_sentences",
        # so we create a temporary table with snapshot's "stories_id" first.
        log.info("Creating a temporary table with snapshot's stories_id...")
        snapshots_stories_id_temp_table_name = 'snapshot_stories_ids_{}'.format(random_string(32))
        db.query("""
            CREATE TEMPORARY TABLE {} AS
                SELECT stories_id
                FROM snap.stories
                WHERE snapshots_id = %(snapshots_id)s
        """.format(snapshots_stories_id_temp_table_name), {'snapshots_id': snapshots_id})

        # "INNER JOIN" instead of "WHERE stories_id IN (SELECT ...)" here because then database doesn't have to compute
        # distinct "stories_id" to SELECT sentence FROM story_sentences against, i.e. it doesn't have to
        # Group + HashAggregate on the temporary table.
        log.info("Creating COPY TO object...")
        self.__copy_to = db.copy_to("""
            COPY (
                SELECT story_sentences.sentence
                FROM {} AS snapshot_stories_ids
                    INNER JOIN story_sentences
                        ON snapshot_stories_ids.stories_id = story_sentences.stories_id
            ) TO STDOUT WITH CSV
        """.format(snapshots_stories_id_temp_table_name))

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
