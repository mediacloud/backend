


-- ALTER TYPE ... ADD VALUE doesn't work in a transaction or a multi-line
-- query, so the new enum value gets added in Schema.pm manually.

--ALTER TYPE feed_feed_type ADD VALUE 'superglue';


--- Superglue (TV) stories metadata -->
CREATE TABLE stories_superglue_metadata (
    stories_superglue_metadata_id   SERIAL    PRIMARY KEY,
    stories_id                      INT       NOT NULL REFERENCES stories ON DELETE CASCADE,
    thumbnail_url                   VARCHAR   NOT NULL,
    segment_duration                NUMERIC   NOT NULL
);

CREATE UNIQUE INDEX stories_superglue_metadata_stories_id
    ON stories_superglue_metadata (stories_id);


