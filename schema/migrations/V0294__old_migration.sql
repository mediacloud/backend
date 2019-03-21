

create index media_annotate on media ( annotate_with_corenlp, media_id );
create index live_stories_story_solo on cd.live_stories ( stories_id );

--
-- Returns true if the story can + should be annotated with CoreNLP
--
CREATE OR REPLACE FUNCTION story_is_annotatable_with_corenlp(corenlp_stories_id INT)
RETURNS boolean AS $$
DECLARE
    story record;
BEGIN

    SELECT stories_id, media_id, language INTO story from stories where stories_id = corenlp_stories_id;

    IF NOT ( story.language = 'en' or story.language is null ) THEN

        RETURN FALSE;

    ELSEIF NOT EXISTS (

            SELECT 1 FROM media WHERE media.annotate_with_corenlp = 't' and media_id = story.media_id

        ) AND NOT EXISTS (

            SELECT 1 FROM extra_corenlp_stories  WHERE extra_corenlp_stories.stories_id = corenlp_stories_id

        ) THEN

        RETURN FALSE;

    ELSEIF NOT EXISTS ( SELECT 1 FROM story_sentences WHERE stories_id = corenlp_stories_id ) THEN

        RETURN FALSE;

    END IF;

    RETURN TRUE;

END;
$$
LANGUAGE 'plpgsql';




