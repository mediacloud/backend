--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4527 and 4528.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4527, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4528, import this SQL file:
--
--     psql mediacloud < mediawords-4527-4528.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

--

alter table stories drop column ap_syndicated;
alter table cd.live_stories drop column ap_syndicated;

create or replace function insert_live_story() returns trigger as $insert_live_story$
    begin

        insert into cd.live_stories
            ( controversies_id, controversy_stories_id, stories_id, media_id, url, guid, title, description,
                publish_date, collect_date, full_text_rss, language,
                db_row_last_updated )
            select NEW.controversies_id, NEW.controversy_stories_id, NEW.stories_id, s.media_id, s.url, s.guid,
                    s.title, s.description, s.publish_date, s.collect_date, s.full_text_rss, s.language,
                    s.db_row_last_updated
                from controversy_stories cs
                    join stories s on ( cs.stories_id = s.stories_id )
                where
                    cs.stories_id = NEW.stories_id and
                    cs.controversies_id = NEW.controversies_id;

        return NEW;
    END;
$insert_live_story$ LANGUAGE plpgsql;

create or replace function update_live_story() returns trigger as $update_live_story$
    begin

        update cd.live_stories set
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

create table stories_ap_syndicated (
    stories_ap_syndicated_id    serial primary key,
    stories_id                  int not null references stories on delete cascade,
    ap_syndicated               boolean not null
);

create unique index stories_ap_syndicated_story on stories_ap_syndicated ( stories_id );

-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4528;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
