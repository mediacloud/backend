


create table controversy_dump_tags (
    controversy_dump_tags_id    serial primary key,
    controversies_id            int not null references controversies on delete cascade,
    tags_id                     int not null references tags
);

alter table controversy_dump_time_slices add tags_id int references tags;

alter table cd.controversy_links_cross_media drop media_name;
alter table cd.controversy_links_cross_media drop ref_media_name;
alter table cd.stories drop description;




