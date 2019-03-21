


-- Remove old stopword tables
DROP TABLE IF EXISTS stopwords_tiny;
DROP TABLE IF EXISTS stopwords_short;
DROP TABLE IF EXISTS stopwords_long;

DROP TABLE IF EXISTS stopword_stems_tiny;
DROP TABLE IF EXISTS stopword_stems_short;
DROP TABLE IF EXISTS stopword_stems_long;

DROP FUNCTION IF EXISTS is_stop_stem(TEXT, TEXT, TEXT);


