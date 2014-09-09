--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4470 and 4471.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4470, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4471, import this SQL file:
--
--     psql mediacloud < mediawords-4470-4471.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--
alter table media_stats drop column mean_num_sentences;
alter table media_stats drop column mean_text_length;
alter table media_stats drop column num_stories_with_sentences;
alter table media_stats drop column num_stories_with_text;

-- update media stats table for new story. create the media / day row if needed.  
create or replace function insert_story_media_stats() returns trigger as $insert_story_media_stats$
begin
    
    insert into media_stats ( media_id, num_stories, num_sentences, stat_date )
        select NEW.media_id, 0, 0, date_trunc( 'day', NEW.publish_date )
            where not exists (
                select 1 from media_stats where media_id = NEW.media_id and stat_date = date_trunc( 'day', NEW.publish_date ) );

    update media_stats set num_stories = num_stories + 1
        where media_id = NEW.media_id and stat_date = date_trunc( 'day', NEW.publish_date );

    return NEW;
END;
$insert_story_media_stats$ LANGUAGE plpgsql;
create trigger stories_insert_story_media_stats after insert 
    on stories for each row execute procedure insert_story_media_stats();


-- update media stats table for updated story date
create function update_story_media_stats() returns trigger as $update_story_media_stats$
declare
    new_date date;
    old_date date;
begin
    
    select date_trunc( 'day', NEW.publish_date ) into new_date;
    select date_trunc( 'day', OLD.publish_date ) into old_date;
    
    IF ( new_date <> old_date ) THEN
        update media_stats set num_stories = num_stories - 1
            where media_id = NEW.media_id and stat_date = old_date;
            
        insert into media_stats ( media_id, num_stories, num_sentences, stat_date )
            select NEW.media_id, 0, 0, date_trunc( 'day', NEW.publish_date )
                where not exists (
                    select 1 from media_stats where media_id = NEW.media_id and stat_date = date_trunc( 'day', NEW.publish_date ) );
            
        update media_stats set num_stories = num_stories + 1
            where media_id = NEW.media_id and stat_date = new_date;
    END IF;

    return NEW;
END;
$update_story_media_stats$ LANGUAGE plpgsql;
create trigger stories_update_story_media_stats after update 
    on stories for each row execute procedure update_story_media_stats();


-- update media stats table for deleted story
create function delete_story_media_stats() returns trigger as $delete_story_media_stats$
begin
    
    update media_stats set num_stories = num_stories - 1
    where media_id = OLD.media_id and stat_date = date_trunc( 'day', OLD.publish_date );

    return NEW;
END;
$delete_story_media_stats$ LANGUAGE plpgsql;
create trigger story_delete_story_media_stats after delete 
    on stories for each row execute procedure delete_story_media_stats();
    
    
-- update media stats table for new story sentence.
create function insert_ss_media_stats() returns trigger as $$
begin
    update media_stats set num_sentences = num_sentences + 1
        where media_id = NEW.media_id and stat_date = date_trunc( 'day', NEW.publish_date );

    return NEW;
END;
$$ LANGUAGE plpgsql;
create trigger ss_insert_story_media_stats after insert 
    on story_sentences for each row execute procedure insert_ss_media_stats();

-- update media stats table for updated story_sentence date
create function update_ss_media_stats() returns trigger as $$
declare
    new_date date;
    old_date date;
begin
    
    select date_trunc( 'day', NEW.publish_date ) into new_date;
    select date_trunc( 'day', OLD.publish_date ) into old_date;
    
    IF ( new_date <> old_date ) THEN
        update media_stats set num_sentences = num_sentences - 1
            where media_id = NEW.media_id and stat_date = old_date;
        update media_stats set num_sentences = num_sentences + 1
            where media_id = NEW.media_id and stat_date = new_date;
    END IF;

    return NEW;
END;
$$ LANGUAGE plpgsql;
create trigger ss_update_story_media_stats after update 
    on story_sentences for each row execute procedure update_ss_media_stats();

-- update media stats table for deleted story sentence
create function delete_ss_media_stats() returns trigger as $$
begin
    
    update media_stats set num_sentences = num_sentences - 1
    where media_id = OLD.media_id and stat_date = date_trunc( 'day', OLD.publish_date );

    return NEW;
END;
$$ LANGUAGE plpgsql;
create trigger story_delete_ss_media_stats after delete 
    on story_sentences for each row execute procedure delete_ss_media_stats();



--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4471;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


