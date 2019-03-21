


--
-- Stories without Readability tag
--
CREATE TABLE IF NOT EXISTS stories_without_readability_tag (
    stories_id BIGINT NOT NULL REFERENCES stories (stories_id)
);
CREATE INDEX stories_without_readability_tag_stories_id
    ON stories_without_readability_tag (stories_id);

-- Fill in the table manually with:
--
-- INSERT INTO scratch.stories_without_readability_tag (stories_id)
--     SELECT stories.stories_id
--     FROM stories
--         LEFT JOIN stories_tags_map
--             ON stories.stories_id = stories_tags_map.stories_id

--             -- "extractor_version:readability-lxml-0.3.0.5"
--             AND stories_tags_map.tags_id = 8929188

--     -- No Readability tag
--     WHERE stories_tags_map.tags_id IS NULL
--     ;


