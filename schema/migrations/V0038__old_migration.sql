


-- To be recreated later on
DROP VIEW media_with_media_types;


DROP TABLE extra_corenlp_stories;

DROP INDEX media_annotate;

ALTER TABLE media
    DROP COLUMN annotate_with_corenlp;

CREATE OR REPLACE FUNCTION story_is_annotatable_with_corenlp(corenlp_stories_id INT) RETURNS boolean AS $$
DECLARE
    story record;
BEGIN

    SELECT stories_id, media_id, language INTO story from stories where stories_id = corenlp_stories_id;

    IF NOT ( story.language = 'en' or story.language is null ) THEN
        RETURN FALSE;

    ELSEIF NOT EXISTS ( SELECT 1 FROM story_sentences WHERE stories_id = corenlp_stories_id ) THEN
        RETURN FALSE;

    END IF;

    RETURN TRUE;

END;
$$
LANGUAGE 'plpgsql';


create view media_with_media_types as
    select m.*, mtm.tags_id media_type_tags_id, t.label media_type
    from
        media m
        left join (
            tags t
            join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id and ts.name = 'media_type' )
            join media_tags_map mtm on ( mtm.tags_id = t.tags_id )
        ) on ( m.media_id = mtm.media_id );


