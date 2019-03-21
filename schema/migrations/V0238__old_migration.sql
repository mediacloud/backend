

ALTER TABLE story_subsets DROP CONSTRAINT story_subsets_media_id_fkey;
ALTER TABLE story_subsets ADD FOREIGN KEY (media_id) REFERENCES media;


