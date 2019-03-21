

begin;

-- create a mirror of the stories table with the stories for each controversy.  this is to make
-- it much faster to query the stories associated with a given controversy, rather than querying the
-- contested and bloated stories table.  only inserts and updates on stories are triggered, because
-- deleted cascading stories_id and controversies_id fields take care of deletes.
create table cd.live_stories (
    controversies_id            int             not null references controversies on delete cascade,
    controversy_stories_id      int             not null references controversy_stories on delete cascade,
    stories_id                  int             not null references stories on delete cascade,
    media_id                    int             not null,
    url                         varchar(1024)   not null,
    guid                        varchar(1024)   not null,
    title                       text            not null,
    description                 text            null,
    publish_date                timestamp       not null,
    collect_date                timestamp       not null,
    full_text_rss               boolean         not null default 'f',
    language                    varchar(3)      null   -- 2- or 3-character ISO 690 language code; empty if unknown, NULL if unset
);
create index live_story_controversy on cd.live_stories ( controversies_id );
create unique index live_stories_story on cd.live_stories ( controversies_id, stories_id );

create function insert_live_story() returns trigger as $insert_live_story$
    begin

        insert into cd.live_stories 
            ( controversies_id, controversy_stories_id, stories_id, media_id, url, guid, title, description, 
                publish_date, collect_date, full_text_rss, language )
            select NEW.controversies_id, NEW.controversy_stories_id, NEW.stories_id, s.media_id, s.url, s.guid, 
                    s.title, s.description, s.publish_date, s.collect_date, s.full_text_rss, s.language
                from controversy_stories cs
                    join stories s on ( cs.stories_id = s.stories_id )
                where 
                    cs.stories_id = NEW.stories_id and 
                    cs.controversies_id = NEW.controversies_id;

        return NEW;
    END;
$insert_live_story$ LANGUAGE plpgsql;

create trigger controversy_stories_insert_live_story after insert on controversy_stories 
    for each row execute procedure insert_live_story();

create function update_live_story() returns trigger as $update_live_story$
    declare
        controversy record;
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
                language = NEW.language
            where
                stories_id = NEW.stories_id;         
        
        return NEW;
    END;
$update_live_story$ LANGUAGE plpgsql;
        
create trigger stories_update_live_story after update on stories 
    for each row execute procedure update_live_story();

insert into cd.live_stories 
    ( controversies_id, controversy_stories_id, stories_id, media_id, url, guid, title, description, 
        publish_date, collect_date, full_text_rss, language )
    select cs.controversies_id, cs.controversy_stories_id, s.stories_id, s.media_id, s.url, s.guid, 
            s.title, s.description, s.publish_date, s.collect_date, s.full_text_rss, s.language
        from controversy_stories cs
            join stories s on ( cs.stories_id = s.stories_id );

commit;

