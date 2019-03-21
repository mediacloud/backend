

create table media_suggestions (
    media_suggestions_id        serial primary key,
    name                        text,
    url                         text not null,
    feed_url                    text,
    reason                      text,
    auth_users_id               int references auth_users on delete set null,
    date_submitted              timestamp not null default now()
);

create index media_suggestions_date on media_suggestions ( date_submitted );

create table media_suggestions_tags_map (
    media_suggestions_id        int references media_suggestions on delete cascade,
    tags_id                     int references tags on delete cascade
);

create index media_suggestions_tags_map_ms on media_suggestions_tags_map ( media_suggestions_id );
create index media_suggestions_tags_map_tag on media_suggestions_tags_map ( tags_id );



