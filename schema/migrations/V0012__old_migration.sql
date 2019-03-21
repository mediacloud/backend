


CREATE OR REPLACE FUNCTION story_is_annotatable_with_corenlp(corenlp_stories_id INT) RETURNS boolean AS $$
BEGIN

    -- FIXME this function is not really optimized for performance

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

    -- Check if the story is extracted
    ELSEIF EXISTS (

        SELECT 1
        FROM downloads
        WHERE stories_id = corenlp_stories_id
          AND type = 'content'
          AND extracted = 'f'

    ) THEN
        RAISE NOTICE 'Story % is not annotatable with CoreNLP because it is not extracted.', corenlp_stories_id;
        RETURN FALSE;

    -- Annotate English language stories only because they're the only ones
    -- supported by CoreNLP at the time.
    ELSEIF NOT EXISTS (

        SELECT 1
        FROM stories
        WHERE stories_id = corenlp_stories_id

        -- Stories with language field set to NULL are the ones fetched before
        -- introduction of the multilanguage support, so they are assumed to be
        -- English.
          AND ( stories.language = 'en' OR stories.language IS NULL )

    ) THEN
        RAISE NOTICE 'Story % is not annotatable with CoreNLP because it is not in English.', corenlp_stories_id;
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


