#!/usr/bin/env python3
#
# Jieba builds a dictionary cache on every load which takes about 0.5 s so here
# we prebuild such a cache
#

import os
from jieba import Tokenizer as JiebaTokenizer

if __name__ == '__main__':
    # Keep in sync with zh/__init__.py
    cache_file = '/var/tmp/jieba.cache'

    jieba = JiebaTokenizer()
    jieba.cache_file = '/var/tmp/jieba.cache'

    dict_base_dir = '/opt/mediacloud/src/common/python/mediawords/languages/zh/'
    dict_path = os.path.join(dict_base_dir, 'dict.txt.big')
    dict_user_path = os.path.join(dict_base_dir, 'userdict.txt')

    assert os.path.isfile(dict_path)
    assert os.path.isfile(dict_user_path)

    jieba.set_dictionary(dict_path)
    jieba.load_userdict(dict_user_path)
    jieba.initialize()

    assert os.path.isfile(cache_file)
