--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4563 and 4564.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4563, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4564, import this SQL file:
--
--     psql mediacloud < mediawords-4563-4564.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

alter table controversies rename to topics;
alter table topics rename controversies_id to topics_id;
alter table topics rename controversy_tag_sets_id to topic_tag_sets_id;

alter index controversies_name rename to topics_name;
alter index controversies_tag_set rename to topics_tag_set;
alter index controversies_media_type_tag_set rename to topics_media_type_tag_set;

drop trigger topic_tag_set;
drop function insert_controversy_tag_set();

create function insert_topic_tag_set() returns trigger as $insert_topic_tag_set$
    begin
        insert into tag_sets ( name, label, description )
            select 'topic_'||NEW.name, NEW.name||' topic', 'Tag set for stories within the '||NEW.name||' topic.';

        select tag_sets_id into NEW.topic_tag_sets_id from tag_sets where name = 'topic_'||NEW.name;

        return NEW;
    END;
$insert_topic_tag_set$ LANGUAGE plpgsql;

create trigger topic_tag_set before insert on topics
    for each row execute procedure insert_topic_tag_set();

alter table controversy_dates rename to topic_dates;

alter table topic_dates rename controversy_dates_id to topic_dates_id;
alter table topic_dates rename controversies_id to topics_id;

drop view controversies_with_dates;

create or replace view topics_with_dates as
    select c.*,
            to_char( cd.start_date, 'YYYY-MM-DD' ) start_date,
            to_char( cd.end_date, 'YYYY-MM-DD' ) end_date
        from
            topics c
            join topic_dates cd on ( c.topics_id = cd.topics_id )
        where
            cd.boundary;

drop table controversy_dump_tags;

alter table controversy_media_codes rename to topic_media_codes;
alter table topic_media_codes rename controversies_id to topics_id;

alter table controversy_merged_stories_map rename to topic_merged_stories_map;

alter index controversy_merged_stories_map_source rename to topic_merged_stories_map_source;
alter index controversy_merged_stories_map_story rename to topic_merged_stories_map_story;

alter table controversy_stories rename to topic_stories;
alter table topic_stories rename controversy_stories_id to topic_stories_id;
alter table topic_stories rename controversies_id to topics_id;

alter index controversy_stories_sc rename to topic_stories_sc;
alter index controversy_stories_controversy rename to topic_stories_topic;

alter table controversy_dead_links rename to topic_dead_links;
alter table topic_dead_links rename controversy_dead_links_id to topic_dead_links_id;
alter table topic_dead_links rename controversies_id to topics_id;

alter table controversy_links rename to topic_links;
alter table topic_links rename controversy_links_id to topic_links_id;
alter table topic_links rename controversies_id to topics_id;

alter table topic_links rename constraint
    controversy_links_controversy_story_stories_id to topic_links_topic_story_stories_id;

alter index controversy_links_scr rename to topic_links_scr;
alter index controversy_links_controversy rename to topic_links_topic;
alter index controversy_links_ref_story rename to topic_links_ref_story;

drop view controversy_links_cross_media;

create or replace view topic_links_cross_media AS
    SELECT s.stories_id,
           sm.name AS media_name,
           r.stories_id AS ref_stories_id,
           rm.name AS ref_media_name,
           cl.url AS url,
           cs.topics_id,
           cl.topic_links_id
    FROM media sm,
         media rm,
         topic_links cl,
         stories s,
         stories r,
         topic_stories cs
    WHERE cl.ref_stories_id != cl.stories_id
      AND s.stories_id = cl.stories_id
      AND cl.ref_stories_id = r.stories_id
      AND s.media_id != r.media_id
      AND sm.media_id = s.media_id
      AND rm.media_id = r.media_id
      AND cs.stories_id = cl.ref_stories_id
      AND cs.topics_id = cl.topics_id;

alter table controversy_seed_urls rename to topic_seed_urls;

alter table topic_seed_urls rename controversy_seed_urls_id to topic_seed_urls_id;
alter table topic_seed_urls rename controversies_id to topics_id;

alter index controversy_seed_urls_controversy rename to topic_seed_urls_topic;
alter index controversy_seed_urls_url rename to topic_seed_urls_url;
alter index controversy_seed_urls_story rename to topic_seed_urls_story;

alter table controversy_ignore_redirects rename to topic_ignore_redirects;

alter table topic_ignore_redirects rename controversy_ignore_redirects_id to topic_ignore_redirects_id;

alter index controversy_ignore_redirects_url rename to topic_ignore_redirects_url;

alter table controversy_query_slices rename to foci;

alter table foci rename controversy_query_slices_id to foci_id;
alter table foci rename controversies_id to topics_id;
alter table foci rename all_time_slices to all_timespans;

alter table controversy_dumps rename to snapshots;

alter table snapshots rename controversy_dumps_id to snapshots_id;
alter table snapshots rename controversies_id to topics_id;
alter table snapshots rename dump_date to snapshot_date;

alter index controversy_dumps_controversy rename to snapshots_topic;

alter table controversy_dump_time_slices rename to timespans;

alter table timespans rename controversy_dump_time_slices_id to timespans_id;
alter table timespans rename controversy_dumps_id to snapshots_id;
alter table timespans rename controversy_query_slices_id to foci_id;

alter index controversy_dump_time_slices_dump rename to timespans_dump;

alter table cdts_files rename to timespan_files;

alter table timespan_files rename cdts_files_id to timespan_files_id;
alter table timespan_files rename controversy_dump_time_slices_id to timespans_id;

alter index cdts_files_cdts rename to timespan_files_timespan;

alter table cd_files rename controversy_dumps_id to snapshots_id;

drop function num_controversy_stories_without_bitly_statistics(param_topics_id INT);

create or replace function num_topic_stories_without_bitly_statistics (param_topics_id INT) RETURNS INT AS
$$
DECLARE
    topic_exists BOOL;
    num_stories_without_bitly_statistics INT;
BEGIN

    SELECT 1 INTO topic_exists
    FROM topics
    WHERE topics_id = param_topics_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'topic % does not exist or is not set up for Bit.ly processing.', param_topics_id;
        RETURN FALSE;
    END IF;

    SELECT COUNT(stories_id) INTO num_stories_without_bitly_statistics
    FROM topic_stories
    WHERE topics_id = param_topics_id
      AND stories_id NOT IN (
        SELECT stories_id
        FROM bitly_clicks_total
    )
    GROUP BY topics_id;
    IF NOT FOUND THEN
        num_stories_without_bitly_statistics := 0;
    END IF;

    RETURN num_stories_without_bitly_statistics;
END;
$$
LANGUAGE plpgsql;

alter table cd.controversy_stories rename to topic_stories;
alter table cd.topic_stories rename controversy_dumps_id to snapshots_id;
alter table cd.topic_stories rename controversy_stories_id to topic_stories_id;
alter table cd.topic_stories rename controversies_id to topics_id;

alter index cd.controversy_stories_id rename to topic_stories_id;

alter table cd.controversy_links_cross_media rename to topic_links_cross_media;
alter table cd.topic_links_cross_media rename controversy_dumps_id to snapshots_id;
alter table cd.topic_links_cross_media rename controversy_links_id to topic_links_id;
alter table cd.topic_links_cross_media rename controversies_id to topics_id;

alter index cd.controversy_links_story rename to topic_links_story;
alter index cd.controversy_links_ref rename to topic_links_ref;

alter table cd.controversy_media_codes rename to topic_media_codes;
alter table cd.topic_media_codes rename controversy_dumps_id to snapshots_id;
alter table cd.topic_media_codes rename controversies_id to topics_id;

alter index cd.controversy_media_codes_medium rename to topic_media_codes_medium;

alter table cd.media rename controversy_dumps_id to snapshots_id;
alter table cd.media_tags_map rename controversy_dumps_id to snapshots_id;
alter table cd.stories rename controversy_dumps_id to snapshots_id;
alter table cd.stories_tags_map rename controversy_dumps_id to snapshots_id;
alter table cd.tags rename controversy_dumps_id to snapshots_id;
alter table cd.tag_sets rename controversy_dumps_id to snapshots_id;
alter table cd.daily_date_counts rename controversy_dumps_id to snapshots_id;
alter table cd.weekly_date_counts rename controversy_dumps_id to snapshots_id;

alter table cd.story_links rename controversy_dump_time_slices_id to timespans_id;
alter table cd.story_link_counts rename controversy_dump_time_slices_id to timespans_id;
alter table cd.medium_link_counts rename controversy_dump_time_slices_id to timespans_id;
alter table cd.medium_links rename controversy_dump_time_slices_id to timespans_id;

alter table cd.live_stories rename controversies_id to topics_id;
alter table cd.live_stories rename controversy_stories_id to topic_stories_id;

alter index cd.live_story_controversy rename to live_story_topic;

drop table cd.word_counts;

alter trigger controversy_stories_insert_live_story on topic_stories rename to topic_stories_insert_live_story;

drop table if exists controversy_query_story_searches_imported_stories_map;

update auth_roles set role = 'tm', description = 'Topic mapper; includes media and story editing' where role = 'cm';
update auth_roles set role = 'tm-readonly', description = 'Topic mapper; excludes media and story editing' where role = 'cm-readonly';

alter type cd_period_type rename to snap_period_type;

alter table cd_files rename to snap_files;

alter table snap_files rename cd_files_id to snap_files_id;

alter schema cd rename to snap;

create or replace function insert_live_story() returns trigger as $insert_live_story$
    begin

        insert into snap.live_stories
            ( topics_id, topic_stories_id, stories_id, media_id, url, guid, title, description,
                publish_date, collect_date, full_text_rss, language,
                db_row_last_updated )
            select NEW.topics_id, NEW.topic_stories_id, NEW.stories_id, s.media_id, s.url, s.guid,
                    s.title, s.description, s.publish_date, s.collect_date, s.full_text_rss, s.language,
                    s.db_row_last_updated
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
                language = NEW.language,
                db_row_last_updated = NEW.db_row_last_updated
            where
                stories_id = NEW.stories_id;

        return NEW;
    END;
$update_live_story$ LANGUAGE plpgsql;

update feeds set name = 'Spider Feed' where name = 'Controversy Spider Feed';

alter table topics drop column has_been_dumped;

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4564;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
