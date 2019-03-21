DROP VIEW media_with_media_types;   -- will recreate right afterwards

ALTER TABLE media
    DROP COLUMN extract_author;

CREATE VIEW media_with_media_types AS
    SELECT m.*, mtm.tags_id media_type_tags_id, t.label media_type
    FROM
        media m
        LEFT JOIN (
            tags t
            JOIN tag_sets ts ON ( ts.tag_sets_id = t.tag_sets_id AND ts.name = 'media_type' )
            JOIN media_tags_map mtm ON ( mtm.tags_id = t.tags_id )
        ) ON ( m.media_id = mtm.media_id );


ALTER TABLE snap.media
    DROP COLUMN extract_author;

