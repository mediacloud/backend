

ALTER TABLE tag_sets
	ADD COLUMN show_on_media_ boolean,
	ADD COLUMN show_on_stories boolean;

ALTER TABLE tags
	ADD COLUMN show_on_media_ boolean,
	ADD COLUMN show_on_stories boolean;


