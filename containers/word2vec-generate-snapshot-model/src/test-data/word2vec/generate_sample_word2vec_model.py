#!/usr/bin/env python3

import gensim

from mediawords.util.log import create_logger
from mediawords.util.test_word2vec import (
    sample_word2vec_model_path,
    sample_word2vec_model_dictionary,
    sample_word2vec_gensim_version_path,
)

log = create_logger(__name__)


def generate_sample_word2vec_model():
    """(Re)generate a sample word2vec model used for testing.

    To ensure that future gensim versions will be able to load models generated
    with a specific gensim version, e.g. gensim==3.2.0:

    1) Install gensim==3.2.0:

        ./script/run_in_env.sh pip3 install gensim==3.2.0

    2) Regenerate sample model with gensim==3.2.0:

        ./script/run_in_env.sh ./tools/word2vec/generate_sample_word2vec_model.py

    3) Commit the sample model to the source tree:

         git add mediacloud/test-data/word2vec/*

    4) Install the newest gensim to test the model loading against:

        ./script/run_in_env.sh pip3 install -U gensim

    5) Run the test_load_word2vec_format() test in test_word2vec.py:

        ./script/run_in_env.sh pytest mediacloud/mediawords/util/test_word2vec.py

    """
    model_path = sample_word2vec_model_path()
    gensim_version_path = sample_word2vec_gensim_version_path()

    log.info("Generating sample word2vec model to '{}'...".format(model_path))
    dictionary = sample_word2vec_model_dictionary()
    model = gensim.models.Word2Vec(
        sentences=dictionary,
        size=100,
        window=5,
        min_count=1,
        workers=4,
    )
    word_vectors = model.wv
    word_vectors.save_word2vec_format(model_path, binary=True)

    log.info("Saving gensim version to '{}'...".format(gensim_version_path))
    with open(gensim_version_path, 'w') as f:
        f.write(gensim.__version__)

    log.info("Done!")


if __name__ == '__main__':
    generate_sample_word2vec_model()
