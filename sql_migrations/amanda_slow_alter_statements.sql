set work_mem='6GB';
UPDATE downloads set extracted = false where extracted is null and type='Calais';

ALTER TABLE downloads
        ALTER COLUMN extracted SET DEFAULT false,
        ALTER COLUMN extracted SET NOT NULL;

ALTER TABLE daily_words
        ALTER COLUMN media_sets_id SET NOT NULL,
        ALTER COLUMN term SET NOT NULL,
        ALTER COLUMN stem SET NOT NULL,
        ALTER COLUMN stem_count SET NOT NULL,
        ALTER COLUMN publish_day SET NOT NULL;

-- ALTER TABLE story_sentence_words
--         ALTER COLUMN stories_id SET NOT NULL,
--         ALTER COLUMN term SET NOT NULL,
--         ALTER COLUMN stem SET NOT NULL,
--         ALTER COLUMN stem_count SET NOT NULL,
--         ALTER COLUMN sentence_number SET NOT NULL,
--         ALTER COLUMN media_id SET NOT NULL,
--         ALTER COLUMN publish_day SET NOT NULL;

ALTER TABLE story_sentences
        ALTER COLUMN story_sentences_id TYPE bigint /* TYPE change - table: story_sentences original: integer new: bigint */,
        ALTER COLUMN stories_id SET NOT NULL,
        ALTER COLUMN sentence_number SET NOT NULL,
        ALTER COLUMN sentence SET NOT NULL,
        ALTER COLUMN media_id SET NOT NULL,
        ALTER COLUMN publish_date SET NOT NULL;

ALTER TABLE downloads
        ADD CONSTRAINT downloads_feeds_id_fkey FOREIGN KEY (feeds_id) REFERENCES feeds(feeds_id);

ALTER TABLE downloads
        ADD CONSTRAINT downloads_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES stories(stories_id) ON DELETE CASCADE;

ALTER TABLE download_texts
        ADD CONSTRAINT download_text_length_is_correct CHECK ((length(download_text) = download_text_length));

ALTER TABLE stories_tags_map
        ADD CONSTRAINT stories_tags_map_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES stories(stories_id) ON DELETE CASCADE;

ALTER TABLE stories_tags_map
        ADD CONSTRAINT stories_tags_map_tags_id_fkey FOREIGN KEY (tags_id) REFERENCES tags(tags_id) ON DELETE CASCADE;

ALTER TABLE story_sentences
        ADD CONSTRAINT story_sentences_media_id_fkey FOREIGN KEY (media_id) REFERENCES media(media_id) ON DELETE CASCADE;

ALTER TABLE story_sentences
        ADD CONSTRAINT story_sentences_stories_id_fkey FOREIGN KEY (stories_id) REFERENCES stories(stories_id) ON DELETE CASCADE;

