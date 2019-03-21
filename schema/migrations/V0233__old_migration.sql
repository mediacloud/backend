


DROP VIEW topics_with_dates;
CREATE VIEW topics_with_dates AS
    select c.*,
            to_char( td.start_date, 'YYYY-MM-DD' ) start_date,
            to_char( td.end_date, 'YYYY-MM-DD' ) end_date
        from
            topics c
            join topic_dates td on ( c.topics_id = td.topics_id )
        where
            td.boundary;


CREATE OR REPLACE FUNCTION insert_live_story() returns trigger as $insert_live_story$
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

CREATE OR REPLACE FUNCTION update_live_story() returns trigger as $update_live_story$
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


