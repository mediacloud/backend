


-- To be recreated later
DROP VIEW media_with_collections;
DROP VIEW media_with_media_types;

DROP INDEX media_moderated;

ALTER TABLE media
    DROP COLUMN moderated,
    DROP COLUMN moderation_notes;

ALTER TABLE snap.media
    DROP COLUMN moderated,
    DROP COLUMN moderation_notes;

CREATE VIEW media_with_collections AS
    SELECT t.tag,
           m.media_id,
           m.url,
           m.name,
           m.full_text_rss
    FROM media m,
         tags t,
         tag_sets ts,
         media_tags_map mtm
    WHERE ts.name::text = 'collection'::text
      AND ts.tag_sets_id = t.tag_sets_id
      AND mtm.tags_id = t.tags_id
      AND mtm.media_id = m.media_id
    ORDER BY m.media_id;

create view media_with_media_types as
    select m.*, mtm.tags_id media_type_tags_id, t.label media_type
    from
        media m
        left join (
            tags t
            join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id and ts.name = 'media_type' )
            join media_tags_map mtm on ( mtm.tags_id = t.tags_id )
        ) on ( m.media_id = mtm.media_id );



