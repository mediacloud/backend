

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
                db_row_last_updated = NEW.db_row_last_updated,
                ap_syndicated = NEW.ap_syndicated
            where
                stories_id = NEW.stories_id;

        return NEW;
    END;
$update_live_story$ LANGUAGE plpgsql;




