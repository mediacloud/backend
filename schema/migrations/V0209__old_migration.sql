


-- Will recreate afterwards
DROP VIEW media_with_media_types;


DROP FUNCTION IF EXISTS purge_story_sentences(date, date);

DROP FUNCTION IF EXISTS media_set_sw_data_retention_dates(int, date, date);

DROP FUNCTION media_set_retains_sw_data_for_date(int, date, date, date);

DROP VIEW media_sets_explict_sw_data_dates;


SET search_path = cd, pg_catalog;
ALTER TABLE media
    DROP COLUMN sw_data_start_date,
    DROP COLUMN sw_data_end_date;


ALTER TABLE media
	DROP COLUMN sw_data_start_date,
	DROP COLUMN sw_data_end_date;


create view media_with_media_types as
    select m.*, mtm.tags_id media_type_tags_id, t.label media_type
    from
        media m
        left join (
            tags t
            join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id and ts.name = 'media_type' )
            join media_tags_map mtm on ( mtm.tags_id = t.tags_id )
        ) on ( m.media_id = mtm.media_id );


