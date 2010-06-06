--This is a short script to update the database to have the archival_only download type
--This script is only useful for mediacloud instances running databases created before mediawords.sql was updated to have archival_only included in the download_type enum

SELECT enum.enum_add('download_type', 'archival_only');

ALTER TABLE downloads drop constraint downloads_feed_id_valid;
alter table downloads add constraint downloads_feed_id_valid
      check ((feeds_id is not null) or 
      ( type = 'spider_blog_home' or type = 'spider_posting' or type = 'spider_rss' or type = 'spider_blog_friends_list' or type = 'archival_only') );

alter table downloads drop constraint downloads_story;
alter table downloads add constraint downloads_story
    check (((type = 'feed' or type = 'spider_blog_home' or type = 'spider_posting' or type = 'spider_rss' or type = 'spider_blog_friends_list' or type = 'archival_only')
    and stories_id is null) or (stories_id is not null));

create view downloads_non_media as select d.* from downloads d where d.feeds_id is null;