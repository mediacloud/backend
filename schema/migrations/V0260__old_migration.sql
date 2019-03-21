


-- Might already exist on production
SELECT create_index_if_not_exists(
    'public',
    'story_sentences',
    'story_sentences_sentence_half_md5',
    '(half_md5(sentence))'
);


