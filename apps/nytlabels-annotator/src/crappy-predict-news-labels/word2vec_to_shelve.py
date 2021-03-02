#!/usr/bin/env python3

"""
Convert Google News model to shelve (https://docs.python.org/3/library/shelve.html) format:

gensim.models.KeyedVectors insists on loading the full model into RAM which takes a lot of resources, so it's cheaper
to store the vocabulary and associated vectors in a disk-backed dictionary such as shelve.

Usage:

    import shelve
    word2vec = shelve.open(...)
    vectors = numpy.frombuffer(word2vec['hello'], dtype=numpy.float32)

"""

import os
import shelve

from gensim.models import KeyedVectors

if __name__ == '__main__':

    sh_vectors_path = 'GoogleNews-vectors-negative300.stripped.shelve'

    if os.path.isfile(sh_vectors_path):
        os.unlink(sh_vectors_path)

    vectors = shelve.open(sh_vectors_path)

    model = KeyedVectors.load_word2vec_format('GoogleNews-vectors-negative300.bin', binary=True)
    word2vec = model.wv

    for term in word2vec.vocab.keys():
        if '/' not in term and '_' not in term:
            vectors[term] = word2vec.vectors[word2vec.vocab[term].index].tobytes()

    vectors.sync()

    vectors.close()
