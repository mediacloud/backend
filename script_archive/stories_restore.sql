create index stories_restore_media_id on stories_restore (media_id);
-- create unique index stories_restore_guid on stories_restore(guid, media_id);
create index stories_restore_url on stories_restore (url);
create index stories_restore_publish_date on stories_restore (publish_date);
create index stories_restore_collect_date on stories_restore (collect_date);
create index stories_restore_title on stories_restore(title, publish_date);