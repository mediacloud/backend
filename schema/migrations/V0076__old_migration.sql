


DROP FUNCTION story_is_annotatable_with_corenlp(corenlp_stories_id INT);

DROP FUNCTION story_is_annotatable_with_cliff(cliff_stories_id INT);

DROP FUNCTION story_is_annotatable_with_nytlabels(nytlabels_stories_id INT);


CREATE OR REPLACE FUNCTION story_is_english_and_has_sentences(param_stories_id INT) RETURNS boolean AS $$
DECLARE
    story record;
BEGIN

    SELECT stories_id, media_id, language INTO story from stories where stories_id = param_stories_id;

    IF NOT ( story.language = 'en' or story.language is null ) THEN
        RETURN FALSE;

    ELSEIF NOT EXISTS ( SELECT 1 FROM story_sentences WHERE stories_id = param_stories_id ) THEN
        RETURN FALSE;

    END IF;

    RETURN TRUE;

END;
$$
LANGUAGE 'plpgsql';



