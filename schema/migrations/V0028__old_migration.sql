


--
-- Returns true if the story can + should be annotated with NYTLabels
--
CREATE OR REPLACE FUNCTION story_is_annotatable_with_nytlabels(nytlabels_stories_id INT)
RETURNS boolean AS $$
DECLARE
    story record;
BEGIN

    SELECT stories_id, media_id, language INTO story from stories where stories_id = nytlabels_stories_id;

    IF NOT ( story.language = 'en' or story.language is null ) THEN
        RETURN FALSE;

    ELSEIF NOT EXISTS ( SELECT 1 FROM story_sentences WHERE stories_id = nytlabels_stories_id ) THEN
        RETURN FALSE;

    END IF;

    RETURN TRUE;

END;
$$
LANGUAGE 'plpgsql';


--
-- NYTLabels annotations
--
CREATE TABLE nytlabels_annotations (
    nytlabels_annotations_id  SERIAL    PRIMARY KEY,
    object_id                 INTEGER   NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,
    raw_data                  BYTEA     NOT NULL
);
CREATE UNIQUE INDEX nytlabels_annotations_object_id ON nytlabels_annotations (object_id);

-- Don't (attempt to) compress BLOBs in "raw_data" because they're going to be
-- compressed already
ALTER TABLE nytlabels_annotations
    ALTER COLUMN raw_data SET STORAGE EXTERNAL;



