

ALTER TABLE tag_sets
	DROP COLUMN show_on_media_,
	ADD COLUMN show_on_media boolean;

ALTER TABLE tags
	DROP COLUMN show_on_media_,
	ADD COLUMN show_on_media boolean;


