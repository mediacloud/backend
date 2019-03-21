


CREATE OR REPLACE FUNCTION insert_ss_media_stats() returns trigger as $$
begin


    IF NOT story_triggers_enabled() THEN
      RETURN NULL;
    END IF;

    update media_stats set num_sentences = num_sentences + 1
        where media_id = NEW.media_id and stat_date = date_trunc( 'day', NEW.publish_date );

    return NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_ss_media_stats() returns trigger as $$
declare
    new_date date;
    old_date date;
begin

    IF NOT story_triggers_enabled() THEN
       RETURN NULL;
    END IF;
    
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

CREATE OR REPLACE FUNCTION delete_ss_media_stats() returns trigger as $$
begin

    IF NOT story_triggers_enabled() THEN
       RETURN NULL;
    END IF;
    
    update media_stats set num_sentences = num_sentences - 1
    where media_id = OLD.media_id and stat_date = date_trunc( 'day', OLD.publish_date );

    return NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION insert_story_media_stats() returns trigger as $insert_story_media_stats$
begin

    IF NOT story_triggers_enabled() THEN
       RETURN NULL;
    END IF;
    
    insert into media_stats ( media_id, num_stories, num_sentences, stat_date )
        select NEW.media_id, 0, 0, date_trunc( 'day', NEW.publish_date )
            where not exists (
                select 1 from media_stats where media_id = NEW.media_id and stat_date = date_trunc( 'day', NEW.publish_date ) );

    update media_stats set num_stories = num_stories + 1
        where media_id = NEW.media_id and stat_date = date_trunc( 'day', NEW.publish_date );

    return NEW;
END;
$insert_story_media_stats$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_story_media_stats() returns trigger as $update_story_media_stats$
declare
    new_date date;
    old_date date;
begin

    IF NOT story_triggers_enabled() THEN
       RETURN NULL;
    END IF;
    
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
            
        update story_sentences set publish_date = new_date where stories_id = OLD.stories_id;
    END IF;

    return NEW;
END;
$update_story_media_stats$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION delete_story_media_stats() returns trigger as $delete_story_media_stats$
begin
    
    IF NOT story_triggers_enabled() THEN
       RETURN NULL;
    END IF;

    update media_stats set num_stories = num_stories - 1
    where media_id = OLD.media_id and stat_date = date_trunc( 'day', OLD.publish_date );

    return NEW;
END;
$delete_story_media_stats$ LANGUAGE plpgsql;

