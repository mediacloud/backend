

alter table topic_fetch_urls add topic_links_id int references topic_links on delete cascade;

create index topic_fetch_urls_url on topic_fetch_urls(md5(url));

update topic_links set link_spidered = 't' where ref_stories_id is not null;



