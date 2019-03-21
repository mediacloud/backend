


ALTER TABLE raw_downloads
    RENAME COLUMN downloads_id TO object_id;

ALTER INDEX raw_downloads_downloads_id
    RENAME TO raw_downloads_object_id;


CREATE TABLE story_sentences_tags_map (
    story_sentences_tags_map_id bigserial  primary key,
    story_sentences_id bigint     not null references story_sentences on delete cascade,
    tags_id int     not null references tags on delete cascade,
    db_row_last_updated timestamp with time zone NOT NULL
);

CREATE INDEX story_sentences_tags_map_db_row_last_updated ON story_sentences_tags_map ( db_row_last_updated );

CREATE UNIQUE INDEX story_sentences_tags_map_story ON story_sentences_tags_map (story_sentences_id, tags_id);

CREATE INDEX story_sentences_tags_map_tag ON story_sentences_tags_map (tags_id);

CREATE INDEX story_sentences_tags_map_story_id ON story_sentences_tags_map USING btree (story_sentences_id);

CREATE TRIGGER story_sentences_tags_map_last_updated_trigger
    BEFORE INSERT OR UPDATE ON story_sentences_tags_map
    FOR EACH ROW
    EXECUTE PROCEDURE last_updated_trigger() ;

CREATE TRIGGER story_sentences_tags_map_update_story_sentences_last_updated_trigger
    AFTER INSERT OR UPDATE OR DELETE ON story_sentences_tags_map
    FOR EACH ROW
    EXECUTE PROCEDURE update_stories_updated_time_by_stories_id_trigger();



