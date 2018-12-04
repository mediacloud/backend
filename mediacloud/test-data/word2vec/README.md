This directory contains a sample pregenerated C-compatible word2vec model to be
used for ensuring that models loaded with older versions of gensim are still
compatible with newer versions of the module.

Files:

* `sample_model.bin` -- sample model to be loaded with `load_word2vec_format()`
* `gensim_version.txt` -- gensim module version that was used for generating
  the sample module.
  
See also:

* `test_load_word2vec_format()` -- test that tries loading a pre-generated
  word2vec module with the currently installed (and potentially newer) version
  of gensim.
* `generate_sample_word2vec_model.py` -- utility to (re)create a sample
  word2vec model.
