#!/usr/bin/env python3

from mediawords.db import connect_to_db
from mediawords.job import AbstractJob, McAbstractJobException, JobBrokerApp
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.word2vec import train_word2vec_model
from mediawords.util.word2vec.model_stores import SnapshotDatabaseModelStore
from mediawords.util.word2vec.sentence_iterators import SnapshotSentenceIterator

log = create_logger(__name__)


class McWord2vecGenerateSnapshotModelException(McAbstractJobException):
    """Word2vecGenerateModel exception."""
    pass


class Word2vecGenerateSnapshotModelJob(AbstractJob):
    """

    Generate word2vec model for a given snapshot.

    Start this worker script by running:

        ./script/run_in_env.sh ./mediacloud/mediawords/job/word2vec/generate_snapshot_model.py

    """

    @classmethod
    def run_job(cls, snapshots_id: int) -> None:

        # MC_REWRITE_TO_PYTHON: remove after Python rewrite
        if isinstance(snapshots_id, bytes):
            snapshots_id = decode_object_from_bytes_if_needed(snapshots_id)

        if snapshots_id is None:
            raise McWord2vecGenerateSnapshotModelException("'snapshots_id' is None.")

        snapshots_id = int(snapshots_id)

        db = connect_to_db()

        log.info("Generating word2vec model for snapshot %d..." % snapshots_id)

        sentence_iterator = SnapshotSentenceIterator(db=db, snapshots_id=snapshots_id)
        model_store = SnapshotDatabaseModelStore(db=db, snapshots_id=snapshots_id)
        train_word2vec_model(sentence_iterator=sentence_iterator,
                             model_store=model_store)

        log.info("Finished generating word2vec model for snapshot %d." % snapshots_id)

    @classmethod
    def queue_name(cls) -> str:
        return 'MediaWords::Job::Word2vec::GenerateSnapshotModel'


if __name__ == '__main__':
    app = JobBrokerApp(job_class=Word2vecGenerateSnapshotModelJob)
    app.start_worker()
