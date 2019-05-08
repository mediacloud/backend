#!/usr/bin/env python3

from mediawords.db import connect_to_db
from mediawords.job import JobBroker
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.word2vec import train_word2vec_model
from mediawords.util.word2vec.model_stores import SnapshotDatabaseModelStore
from mediawords.util.word2vec.sentence_iterators import SnapshotSentenceIterator

log = create_logger(__name__)


class McWord2vecGenerateSnapshotModelException(Exception):
    """Word2vecGenerateModel exception."""
    pass


def run_word2vec_generate_snapshot_model(snapshots_id: int) -> None:
    """Generate word2vec model for a given snapshot."""

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


if __name__ == '__main__':
    app = JobBroker(queue_name='MediaWords::Job::Word2vec::GenerateSnapshotModel')
    app.start_worker(handler=run_word2vec_generate_snapshot_model)
