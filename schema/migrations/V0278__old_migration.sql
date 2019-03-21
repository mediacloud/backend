

ALTER TABLE stories
	ADD COLUMN disable_triggers boolean;

ALTER TABLE story_sentences
	ADD COLUMN disable_triggers boolean;

ALTER TABLE processed_stories
	ADD COLUMN disable_triggers boolean;


