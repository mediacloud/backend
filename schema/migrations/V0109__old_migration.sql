

drop trigger mtm_last_updated on media_tags_map;
drop trigger stories_last_updated_trigger on stories;
drop trigger stories_update_story_sentences_last_updated_trigger on stories;
drop trigger stories_tags_map_last_updated_trigger on stories_tags_map;
drop trigger stories_tags_map_update_stories_last_updated_trigger on stories_tags_map;
drop trigger story_sentences_nonpartitioned_last_updated_trigger on story_sentences_nonpartitioned;
drop trigger story_sentences_partitioned_00_last_updated_trigger on story_sentences_partitioned;
drop trigger processed_stories_update_stories_last_updated_trigger on processed_stories;
drop trigger update_media_db_row_last_updated on media;

drop function before_last_solr_import(timestamp with time zone);
drop function last_updated_trigger();
drop function update_story_sentences_updated_time_trigger();
drop function update_stories_updated_time_by_stories_id_trigger();

alter table media add normalized_url varchar(1024) null;

drop view media_with_media_types;
alter table media drop column db_row_last_updated; 
create view media_with_media_types as
    select m.*, mtm.tags_id media_type_tags_id, t.label media_type
    from
        media m
        left join (
            tags t
            join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id and ts.name = 'media_type' )
            join media_tags_map mtm on ( mtm.tags_id = t.tags_id )
        ) on ( m.media_id = mtm.media_id );

create index media_normalized_url on media(normalized_url);

drop function update_media_db_row_last_updated();
drop table media_normalized_urls;
drop table media_update_time_queue;

drop view daily_stats;
drop view stories_collected_in_past_day;

alter table stories drop column db_row_last_updated;


CREATE VIEW stories_collected_in_past_day AS
    SELECT *
    FROM stories
    WHERE collect_date > now() - interval '1 day';

CREATE VIEW daily_stats AS
    SELECT *
    FROM (
            SELECT COUNT(*) AS daily_downloads
            FROM downloads_in_past_day
         ) AS dd,
         (
            SELECT COUNT(*) AS daily_stories
            FROM stories_collected_in_past_day
         ) AS ds,
         (
            SELECT COUNT(*) AS downloads_to_be_extracted
            FROM downloads_to_be_extracted
         ) AS dex,
         (
            SELECT COUNT(*) AS download_errors
            FROM downloads_with_error_in_past_day
         ) AS er,
         (
            SELECT COALESCE( SUM( num_stories ), 0  ) AS solr_stories
            FROM solr_imports WHERE import_date > now() - interval '1 day'
         ) AS si;


create function insert_solr_import_story() returns trigger as $insert_solr_import_story$
DECLARE

    queue_stories_id INT;

BEGIN

    IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') THEN
        select NEW.stories_id into queue_stories_id;
    ELSE
        select OLD.stories_id into queue_stories_id;
	END IF;

    insert into solr_import_stories ( stories_id )
        select queue_stories_id
            where exists (
                select 1 from processed_stories where stories_id = queue_stories_id
         );

    IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') THEN
		RETURN NEW;
	ELSE
		RETURN OLD;
	END IF;

END;

$insert_solr_import_story$ LANGUAGE plpgsql;

create trigger stories_insert_solr_import_story after insert or update or delete
    on stories for each row execute procedure insert_solr_import_story();

alter table stories_tags_map drop column db_row_last_updated;

create trigger stm_insert_solr_import_story before insert or update or delete
    on stories_tags_map for each row execute procedure insert_solr_import_story();

drop view story_sentences;

alter table story_sentences_partitioned drop column db_row_last_updated;
 
-- recreate this function without db_row_last_updated function
CREATE OR REPLACE FUNCTION story_sentences_create_partitions()
RETURNS VOID AS
$$
DECLARE
    created_partitions TEXT[];
    partition TEXT;
BEGIN

    created_partitions := ARRAY(SELECT stories_create_partitions('story_sentences_partitioned'));

    FOREACH partition IN ARRAY created_partitions LOOP

        RAISE NOTICE 'Altering created partition "%"...', partition;
        
        EXECUTE '
            ALTER TABLE ' || partition || '
                ADD CONSTRAINT ' || REPLACE(partition, '.', '_') || '_media_id_fkey
                FOREIGN KEY (media_id) REFERENCES media (media_id) MATCH FULL ON DELETE CASCADE;

            CREATE UNIQUE INDEX ' || partition || '_stories_id_sentence_number
                ON ' || partition || ' (stories_id, sentence_number);

            CREATE INDEX ' || partition || '_sentence_media_week
                ON ' || partition || ' (half_md5(sentence), media_id, week_start_date(publish_date::date));
        ';

    END LOOP;

END;
$$
LANGUAGE plpgsql;


CREATE FUNCTION edit_ss()
RETURNS VOID AS
$$
DECLARE
    created_partitions TEXT[];
    partition TEXT;
BEGIN

    created_partitions := ARRAY(SELECT stories_create_partitions('story_sentences_partitioned'));

    FOREACH partition IN ARRAY created_partitions LOOP

        RAISE NOTICE 'Altering created partition "%"...', partition;
        
        EXECUTE 'DROP INDEX ' || partition || '_db_row_last_updated;';

    END LOOP;

END;
$$
LANGUAGE plpgsql;

select edit_ss();

drop function edit_ss();

-- replace with version without db_row_last_updated
CREATE OR REPLACE VIEW story_sentences AS

    SELECT *
    FROM (
        SELECT
            story_sentences_partitioned_id AS story_sentences_id,
            stories_id,
            sentence_number,
            sentence,
            media_id,
            publish_date,
            language,
            is_dup
        FROM story_sentences_partitioned

        UNION ALL

        SELECT
            story_sentences_nonpartitioned_id AS story_sentences_id,
            stories_id,
            sentence_number,
            sentence,
            media_id,
            publish_date,
            language,
            is_dup
        FROM story_sentences_nonpartitioned

    ) AS ss;

-- replace with version without db_row_last_updated 
CREATE OR REPLACE FUNCTION story_sentences_view_insert_update_delete() RETURNS trigger AS $$

DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "story_sentences_01")

BEGIN

    IF (TG_OP = 'INSERT') THEN

        -- All new INSERTs go to partitioned table only.
        --
        -- By INSERTing into the master table, we're letting triggers choose
        -- the correct partition.
        INSERT INTO story_sentences_partitioned SELECT NEW.*;

        RETURN NEW;

    ELSIF (TG_OP = 'UPDATE') THEN

        -- UPDATE on both tables

        UPDATE story_sentences_partitioned
            SET stories_id = NEW.stories_id,
                sentence_number = NEW.sentence_number,
                sentence = NEW.sentence,
                media_id = NEW.media_id,
                publish_date = NEW.publish_date,
                language = NEW.language,
                is_dup = NEW.is_dup
            WHERE stories_id = OLD.stories_id
              AND sentence_number = OLD.sentence_number;

        UPDATE story_sentences_nonpartitioned
            SET stories_id = NEW.stories_id,
                sentence_number = NEW.sentence_number,
                sentence = NEW.sentence,
                media_id = NEW.media_id,
                publish_date = NEW.publish_date,
                language = NEW.language,
                is_dup = NEW.is_dup
            WHERE stories_id = OLD.stories_id
              AND sentence_number = OLD.sentence_number;

        RETURN NEW;

    ELSIF (TG_OP = 'DELETE') THEN

        -- DELETE from both tables

        DELETE FROM story_sentences_partitioned
            WHERE stories_id = OLD.stories_id
              AND sentence_number = OLD.sentence_number;

        DELETE FROM story_sentences_nonpartitioned
            WHERE stories_id = OLD.stories_id
              AND sentence_number = OLD.sentence_number;

        -- Return deleted rows
        RETURN OLD;

    ELSE
        RAISE EXCEPTION 'Unconfigured operation: %', TG_OP;

    END IF;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER story_sentences_view_insert_update_delete_trigger
    INSTEAD OF INSERT OR UPDATE OR DELETE ON story_sentences
    FOR EACH ROW EXECUTE PROCEDURE story_sentences_view_insert_update_delete();

ALTER VIEW story_sentences
    ALTER COLUMN story_sentences_id
    SET DEFAULT nextval(pg_get_serial_sequence('story_sentences_partitioned', 'story_sentences_partitioned_id')) + 1;
    
CREATE OR REPLACE FUNCTION copy_chunk_of_nonpartitioned_sentences_to_partitions(start_stories_id INT, end_stories_id INT)
RETURNS INT AS $$

DECLARE
    copied_sentence_count INT;

    -- Partition table names for both stories_id bounds
    start_stories_id_table_name TEXT;
    end_stories_id_table_name TEXT;

BEGIN

    IF NOT (start_stories_id < end_stories_id) THEN
        RAISE EXCEPTION '"end_stories_id" must be bigger than "start_stories_id".';
    END IF;

    SELECT stories_partition_name('story_sentences_partitioned', start_stories_id)
        INTO start_stories_id_table_name;
    IF NOT (table_exists(start_stories_id_table_name)) THEN
        RAISE EXCEPTION
            'Table "%" for "start_stories_id" = % does not exist.',
            start_stories_id_table_name, start_stories_id;
    END IF;

    SELECT stories_partition_name('story_sentences_partitioned', end_stories_id)
        INTO end_stories_id_table_name;
    IF NOT (table_exists(end_stories_id_table_name)) THEN
        RAISE EXCEPTION
            'Table "%" for "end_stories_id" = % does not exist.',
            end_stories_id_table_name, end_stories_id;
    END IF;

    IF NOT (start_stories_id_table_name = end_stories_id_table_name) THEN
        RAISE EXCEPTION
            '"start_stories_id" = % and "end_stories_id" = % must be within the same partition.',
            start_stories_id, end_stories_id;
    END IF;

    -- Kill all autovacuums before proceeding with DDL changes
    PERFORM pid
    FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
    WHERE backend_type = 'autovacuum worker'
      AND query ~ 'story_sentences';

    RAISE NOTICE
        'Copying sentences of stories_id BETWEEN % AND % to the partitioned table...',
        start_stories_id, end_stories_id;

    EXECUTE '

        -- Fetch and delete sentences within bounds
        WITH deleted_rows AS (
            DELETE FROM story_sentences_nonpartitioned
            WHERE stories_id BETWEEN ' || start_stories_id || ' AND ' || end_stories_id || '
            RETURNING story_sentences_nonpartitioned.*
        ),

        -- Deduplicate sentences: nonpartitioned table has weird duplicates,
        -- and the new index insists on (stories_id, sentence_number)
        -- uniqueness (which is a logical assumption to make)
        --
        -- Assume that the sentence with the biggest story_sentences_id is the
        -- newest one and so is the one that we want.
        deduplicated_rows AS (
            SELECT DISTINCT ON (stories_id, sentence_number) *
            FROM deleted_rows
            ORDER BY stories_id, sentence_number, story_sentences_nonpartitioned_id DESC
        )

        -- INSERT directly into the partition to circumvent slow insertion
        -- trigger on "story_sentences" view
        INSERT INTO ' || start_stories_id_table_name || ' (
            story_sentences_partitioned_id,
            stories_id,
            sentence_number,
            sentence,
            media_id,
            publish_date,
            language,
            is_dup
        )
        SELECT
            story_sentences_nonpartitioned_id,
            stories_id,
            sentence_number,
            sentence,
            media_id,
            publish_date,
            language,
            is_dup
        FROM deduplicated_rows;

    ';

    GET DIAGNOSTICS copied_sentence_count = ROW_COUNT;

    RAISE NOTICE
        'Finished copying sentences of stories_id BETWEEN % AND % to the partitioned table, copied % sentences.',
        start_stories_id, end_stories_id, copied_sentence_count;

    RETURN copied_sentence_count;

END;
$$
LANGUAGE plpgsql;

alter table solr_import_extra_stories rename to solr_import_stories;
 
alter table snap.live_stories drop column db_row_last_updated;

create or replace function insert_live_story() returns trigger as $insert_live_story$
    begin

        insert into snap.live_stories
            ( topics_id, topic_stories_id, stories_id, media_id, url, guid, title, description,
                publish_date, collect_date, full_text_rss, language )
            select NEW.topics_id, NEW.topic_stories_id, NEW.stories_id, s.media_id, s.url, s.guid,
                    s.title, s.description, s.publish_date, s.collect_date, s.full_text_rss, s.language
                from topic_stories cs
                    join stories s on ( cs.stories_id = s.stories_id )
                where
                    cs.stories_id = NEW.stories_id and
                    cs.topics_id = NEW.topics_id;

        return NEW;
    END;
$insert_live_story$ LANGUAGE plpgsql;

create or replace function update_live_story() returns trigger as $update_live_story$
    begin

        update snap.live_stories set
                media_id = NEW.media_id,
                url = NEW.url,
                guid = NEW.guid,
                title = NEW.title,
                description = NEW.description,
                publish_date = NEW.publish_date,
                collect_date = NEW.collect_date,
                full_text_rss = NEW.full_text_rss,
                language = NEW.language
            where
                stories_id = NEW.stories_id;

        return NEW;
    END;
$update_live_story$ LANGUAGE plpgsql;


create trigger ps_insert_solr_import_story after insert or update or delete
    on processed_stories for each row execute procedure insert_solr_import_story();
 



