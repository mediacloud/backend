

alter table topics add start_date date;
alter table topics add end_date date;

update topics t set start_date = td.start_date, end_date = td.end_date
        from topic_dates td
        where
            t.topics_id = td.topics_id and
            td.boundary;

alter table topics alter start_date set not null;
alter table topics alter end_date set not null;

drop view topics_with_dates;
drop table if exists snapshot_tags;

create table topics_media_map (
    topics_id       int not null references topics on delete cascade,
    media_id        int not null references media on delete cascade
);

create index topics_media_map_topic on topics_media_map ( topics_id );

create table topics_media_tags_map (
    topics_id       int not null references topics on delete cascade,
    tags_id         int not null references tags on delete cascade
);

create index topics_media_tags_map_topic on topics_media_tags_map ( topics_id );




