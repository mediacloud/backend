

-- dates on which feeds have been scraped with MediaWords::ImportStories and the module used for scraping
create table scraped_feeds (
    scraped_feeds_id        serial primary key,
    feeds_id                int not null references feeds on delete cascade,
    scrape_date             timestamp not null default now(),
    import_module           text not null
);

create index scraped_feeds_feed on scraped_feeds ( feeds_id );

create view feedly_unscraped_feeds as
    select f.*
        from feeds f
            left join scraped_feeds sf on
                ( f.feeds_id = sf.feeds_id and sf.import_module = 'MediaWords::ImportStories::Feedly' )
        where
            f.feed_type = 'syndicated' and
            f.feed_status = 'active' and
            sf.feeds_id is null;
            


