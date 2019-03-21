

ALTER TABLE stories_tags_map
	ALTER COLUMN db_row_last_updated SET DEFAULT now();

ALTER TABLE story_sentences_tags_map
	ALTER COLUMN db_row_last_updated SET DEFAULT now();


