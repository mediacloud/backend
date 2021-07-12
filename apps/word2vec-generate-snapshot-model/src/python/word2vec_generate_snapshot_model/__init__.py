import os
import shutil
import tempfile

import gensim

from mediawords.util.log import create_logger
from word2vec_generate_snapshot_model.exceptions import McWord2vecException
from word2vec_generate_snapshot_model.model_stores import AbstractModelStore
from word2vec_generate_snapshot_model.sentence_iterators import AbstractSentenceIterator

log = create_logger(__name__)


def train_word2vec_model(sentence_iterator: AbstractSentenceIterator,
                         model_store: AbstractModelStore) -> int:
    """Train word2vec model.

    :param sentence_iterator: Sentence iterator to fetch training sentences from
    :param model_store: Model store to write the trained model to
    :return ID of the model that was generated
    """

    temp_directory = tempfile.mkdtemp()
    temp_model_path = os.path.join(temp_directory, 'model.word2vec')

    # Occupy only a single code to leave resources for other stuff to happen on the machine
    worker_count = 1

    word2vec_min_count = 1
    word2vec_size = 100
    word2vec_max_vocab_size = 5000

    log.info("Creating model...")
    model = gensim.models.Word2Vec(
        sentences=sentence_iterator,
        size=word2vec_size,
        min_count=word2vec_min_count,
        workers=worker_count,
        max_vocab_size=word2vec_max_vocab_size,
    )

    # No model trimming (by converting it to KeyedVectors) to avoid compatibility issues
    # (https://github.com/RaRe-Technologies/gensim/issues/2201)

    log.info("Trimming model...")
    word_vectors = model.wv
    del model

    # Saving in in the same format used by the original C word2vec-tool, for compatibility
    log.info("Saving model to a temporary path '%s'..." % temp_model_path)
    word_vectors.save_word2vec_format(temp_model_path, binary=True)

    if not os.path.isfile(temp_model_path):
        raise McWord2vecException("word2vec model not found at path: %s" % temp_model_path)

    log.info("Reading model from a temporary path...")
    with open(temp_model_path, mode='rb') as model_file:
        model_data = model_file.read()

    log.info("Storing model to in a model store...")
    models_id = model_store.store_model(topics_id=topics_id, model_data=model_data)

    log.info("Cleaning up temporary directory '%s'..." % temp_directory)
    shutil.rmtree(temp_directory)

    log.info("Done!")

    return models_id
