

ALTER TABLE media_edits
	-- Don't reference the "media" table in the SQL diff because ALTER TABLE
	-- will fill "media_id" with zeroes, and media.media_id = 0 might not exist.
	--
	-- Also, make the default value of media_edits.media_id = 0 because at this
	-- point we don't know which specific media was edited (someone has to
	-- create those references by hand).
	--
	-- Later, after creating manual references from media_edits.media_id to
	-- media.media_id, one should ALTER this table further as such:
	--
	--     ALTER TABLE media_edits ALTER COLUMN media_id DROP DEFAULT;
	--     ALTER TABLE media_edits ADD CONSTRAINT media_edits_media_id_fkey
	--         FOREIGN KEY (media_id) REFERENCES media(media_id)
	--         ON DELETE NO ACTION ON UPDATE NO ACTION DEFERRABLE;
    --
	ADD COLUMN media_id INT         NOT NULL DEFAULT 0;

CREATE INDEX media_edits_media_id ON media_edits (media_id);
CREATE INDEX media_edits_edited_field ON media_edits (edited_field);
CREATE INDEX media_edits_users_email ON media_edits (users_email);
CREATE INDEX story_edits_stories_id ON story_edits (stories_id);
CREATE INDEX story_edits_edited_field ON story_edits (edited_field);
CREATE INDEX story_edits_users_email ON story_edits (users_email);




