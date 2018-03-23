import os
import shutil
import tempfile

import gensim

from mediawords.util.log import create_logger
from mediawords.util.word2vec.exceptions import McWord2vecException
from mediawords.util.word2vec.model_stores import AbstractModelStore
from mediawords.util.word2vec.sentence_iterators import AbstractSentenceIterator

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
    model = gensim.models.Word2Vec(sentences=sentence_iterator,
                                   size=word2vec_size,
                                   min_count=word2vec_min_count,
                                   workers=worker_count,
                                   max_vocab_size=word2vec_max_vocab_size)

    log.info("Trimming model...")
    word_vectors = model.wv
    del model

    log.info("Saving model to a temporary path '%s'..." % temp_model_path)
    # Clients will be loading the model using Python 2.7 which doesn't support protocols >= 3
    pickle_protocol = 2
    word_vectors.save(temp_model_path, pickle_protocol=pickle_protocol)

    if not os.path.isfile(temp_model_path):
        raise McWord2vecException("word2vec model not found at path: %s" % temp_model_path)

    log.info("Reading model from a temporary path...")
    with open(temp_model_path, mode='rb') as model_file:
        model_data = model_file.read()

    log.info("Storing model to in a model store...")
    models_id = model_store.store_model(model_data=model_data)

    log.info("Cleaning up temporary directory '%s'..." % temp_directory)
    shutil.rmtree(temp_directory)

    log.info("Done!")

    return models_id


# MC_REWRITE_TO_PYTHON: make it return a file-like object instead of copying the whole model into 'bytes'
def load_word2vec_model(model_store: AbstractModelStore, models_id: int) -> bytes:
    """Load word2vec model.

    :param model_store: Model store to load the model from
    :param models_id: Model ID to load
    """
    return model_store.read_model(models_id=models_id)
