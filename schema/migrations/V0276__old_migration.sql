
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






