


CREATE OR REPLACE FUNCTION story_is_annotatable_with_corenlp(corenlp_stories_id INT) RETURNS boolean AS $$
BEGIN

    IF EXISTS (

        SELECT 1
        FROM stories
            INNER JOIN media ON stories.media_id = media.media_id
        WHERE stories.stories_id = corenlp_stories_id

          -- We don't check if the story has been extracted here because the
          -- CoreNLP worker might get to it sooner than the extractor (i.e. the
          -- extractor might not be fast enough to set extracted = 't' before
          -- CoreNLP annotation begins)

          -- Media is marked for CoreNLP annotation
          AND media.annotate_with_corenlp = 't'

          -- English language stories only because they're the only ones
          -- supported by CoreNLP at the time.
          -- Stories with language field set to NULL are the ones fetched
          -- before introduction of the multilanguage support, so they are
          -- assumed to be in English
          AND (stories.language = 'en' OR stories.language IS NULL)

          -- Story not yet marked as "processed"
          AND NOT EXISTS (
            SELECT 1
            FROM processed_stories
            WHERE stories.stories_id = processed_stories.stories_id
          )

    ) THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
    
END;
$$
LANGUAGE 'plpgsql';




