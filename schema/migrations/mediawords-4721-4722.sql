--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4721 and 4722.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4721, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4722, import this SQL file:
--
--     psql mediacloud < mediawords-4721-4722.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

alter table stories add column if not exists normalized_title_hash       uuid            null;
create index if not exists stories_normalized_title_hash on stories( media_id, normalized_title_hash );

CREATE OR REPLACE FUNCTION get_normalized_title(title text, title_media_id int)
 RETURNS text
 IMMUTABLE
AS $function$
declare
        title_part text;
        media_title text;
begin

        -- stupid simple html stripper to avoid html messing up title_parts
        select into title regexp_replace(title, '<[^\<]*>', '', 'gi');
        select into title regexp_replace(title, '\&#?[a-z0-9]*', '', 'gi');

        select into title lower(title);
        select into title regexp_replace(title,'(?:\- )|[:|]', 'SEPSEP', 'g');
        select into title regexp_replace(title, '[[:punct:]]', '', 'g');
        select into title regexp_replace(title, '\s+', ' ', 'g');
        select into title substr(title, 0, 1024);

        if title_media_id = 0 then
            return title;
        end if;

        select into title_part part
            from ( select regexp_split_to_table(title, ' *SEPSEP *') part ) parts
            order by length(part) desc limit 1;

        if title_part = title then
            return title;
        end if;

        if length(title_part) < 32 then
            return title;
        end if;

        select into media_title get_normalized_title(name, 0) from media where media_id = title_media_id;
        if media_title = title_part then
            return title;
        end if;

        return title_part;
end
$function$ language plpgsql;

create or replace function add_normalized_title_hash() returns trigger as $function$
BEGIN

    if ( TG_OP = 'update' ) then
        if ( OLD.title = NEW.title ) then
            return new;
        end if;
    end if;

    select into NEW.normalized_title_hash md5( get_normalized_title( NEW.title, NEW.media_id ) )::uuid;
    
    return new;

END

$function$ language plpgsql;

drop trigger if exists stories_add_normalized_title on stories;
create trigger stories_add_normalized_title before insert or update
    on stories for each row execute procedure add_normalized_title_hash();

-- list of all url or guid identifiers for each story
create table if not exists story_urls (
    story_urls_id   bigserial primary key,
    stories_id      int references stories on delete cascade,
    url             varchar(1024) not null
);

create unique index if not exists story_urls_url on story_urls ( url, stories_id );
create index if not exists stories_story on story_urls ( stories_id );

alter table snap.live_stories add column if not exists normalized_title_hash       uuid            null;
create index if not exists live_stories_title_hash
    on snap.live_stories ( topics_id, media_id, date_trunc('day', publish_date), normalized_title_hash );


create or replace function insert_live_story() returns trigger as $insert_live_story$
    begin

        insert into snap.live_stories
            ( topics_id, topic_stories_id, stories_id, media_id, url, guid, title, normalized_title_hash, description,
                publish_date, collect_date, full_text_rss, language )
            select NEW.topics_id, NEW.topic_stories_id, NEW.stories_id, s.media_id, s.url, s.guid,
                    s.title, s.normalized_title_hash, s.description, s.publish_date, s.collect_date, s.full_text_rss,
                    s.language
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
                normalized_title_hash = NEW.normalized_title_hash,
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

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4722;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


