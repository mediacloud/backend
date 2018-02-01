#!/usr/bin/env python3.5

from mediawords.db import connect_to_db
from mediawords.job import AbstractJob, McAbstractJobException, JobBrokerApp
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.word2vec import train_word2vec_model
from mediawords.util.word2vec.model_stores import TopicDatabaseModelStore
from mediawords.util.word2vec.sentence_iterators import TopicSentenceIterator

log = create_logger(__name__)


class McWord2vecGenerateTopicModelException(McAbstractJobException):
    """Word2vecGenerateModel exception."""
    pass


class Word2vecGenerateTopicModelJob(AbstractJob):
    """

    Generate word2vec model for a given topic.

    Start this worker script by running:

        ./script/run_in_env.sh ./mediacloud/mediawords/job/word2vec/generate_topic_model.py

    """

    @classmethod
    def run_job(cls, topics_id: int) -> None:

        # MC_REWRITE_TO_PYTHON: remove after Python rewrite
        if isinstance(topics_id, bytes):
            topics_id = decode_object_from_bytes_if_needed(topics_id)

        if topics_id is None:
            raise McWord2vecGenerateTopicModelException("'topics_id' is None.")

        topics_id = int(topics_id)

        db = connect_to_db()

        log.info("Generating word2vec model for topic %d..." % topics_id)

        sentence_iterator = TopicSentenceIterator(db=db, topics_id=topics_id)
        model_store = TopicDatabaseModelStore(db=db, topics_id=topics_id)
        train_word2vec_model(sentence_iterator=sentence_iterator,
                             model_store=model_store)

        log.info("Finished generating word2vec model for topic %d." % topics_id)

    @classmethod
    def queue_name(cls) -> str:
        return 'MediaWords::Job::Word2vec::GenerateTopicModel'


if __name__ == '__main__':
    app = JobBrokerApp(job_class=Word2vecGenerateTopicModelJob)
    app.start_worker()
