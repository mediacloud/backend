

-- list of stories that have been imported from feedly
create table scraped_stories (
    scraped_stories_id      serial primary key,
    stories_id              int not null references stories on delete cascade,
    import_module           text not null
);

create index scraped_stories_story on scraped_stories ( stories_id );



