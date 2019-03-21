


ALTER TABLE stories_superglue_metadata
    ADD COLUMN video_url VARCHAR NOT NULL DEFAULT '';

-- Copy story (video) URLs to metadata table
UPDATE stories_superglue_metadata
SET video_url = superglue_stories.url
FROM (
    SELECT stories_id,
           url
    FROM stories
    WHERE stories_id IN (
        SELECT stories_id
        FROM feeds_stories_map
        WHERE feeds_id IN (
            SELECT feeds_id
            FROM feeds
            WHERE feed_type = 'superglue'
        )
    )
) AS superglue_stories
WHERE stories_superglue_metadata.stories_id = superglue_stories.stories_id;

-- Remove URLs (set to GUID) from "stories" table
UPDATE stories
SET url = guid
WHERE stories_id IN (
    SELECT stories_id
    FROM feeds_stories_map
    WHERE feeds_id IN (
        SELECT feeds_id
        FROM feeds
        WHERE feed_type = 'superglue'
    )
);

ALTER TABLE stories_superglue_metadata
    ALTER COLUMN video_url DROP DEFAULT;



