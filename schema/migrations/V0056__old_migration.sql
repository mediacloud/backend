


--
-- Returns true if the story can + should be annotated with CoreNLP
--
CREATE OR REPLACE FUNCTION story_is_annotatable_with_corenlp(corenlp_stories_id INT) RETURNS boolean AS $$
BEGIN

    -- Check "media.annotate_with_corenlp"
    IF NOT EXISTS (

        SELECT 1
        FROM stories
            INNER JOIN media ON stories.media_id = media.media_id
        WHERE stories.stories_id = corenlp_stories_id
          AND media.annotate_with_corenlp = 't'

    ) THEN
        RAISE NOTICE 'Story % is not annotatable with CoreNLP because media is not set for annotation.', corenlp_stories_id;
        RETURN FALSE;

    -- Check if story has sentences
    ELSEIF NOT EXISTS (

        SELECT 1
        FROM story_sentences
        WHERE stories_id = corenlp_stories_id

    ) THEN
        RAISE NOTICE 'Story % is not annotatable with CoreNLP because it has no sentences.', corenlp_stories_id;
        RETURN FALSE;

    -- Things are fine
    ELSE
        RETURN TRUE;

    END IF;
    
END;
$$
LANGUAGE 'plpgsql';




