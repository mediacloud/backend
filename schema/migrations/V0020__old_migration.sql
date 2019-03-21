

create table controversy_dead_links (
    controversy_dead_links_id   serial primary key,
    controversies_id            int not null,
    stories_id                  int not null,
    url                         text not null
);



