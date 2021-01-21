#!/usr/bin/env python3

"""
Convert Google News model to KeyedVectors format:

* We can load it and share among workers using mmap()
* Loads faster
* Uses at least 2x less memory
"""

from gensim.models import KeyedVectors

if __name__ == '__main__':
    model = KeyedVectors.load_word2vec_format('GoogleNews-vectors-negative300.bin', binary=True)
    model.save('GoogleNews-vectors-negative300.keyedvectors')
