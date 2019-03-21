


CREATE INDEX IF NOT EXISTS downloads_story_not_null
    ON downloads (stories_id)
    WHERE stories_id IS NOT NULL;


-- Needed for effective migration to a partitioned table
CREATE INDEX IF NOT EXISTS downloads_type
    ON downloads (type);



