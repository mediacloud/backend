

create table mediacloud_stats (
    stats_date              date not null default now(),
    daily_downloads         bigint not null,
    daily_stories           bigint not null,
    active_crawled_media    bigint not null,
    active_crawled_feeds    bigint not null,
    total_stories           bigint not null,
    total_downloads         bigint not null,
    total_sentences         bigint not null
);

alter table media add primary_language            varchar( 4 ) null;



