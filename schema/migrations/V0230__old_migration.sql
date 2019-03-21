

create table api_links (
    api_links_id        bigserial primary key,
    path                text not null,
    params_json         text not null,
    next_link_id        bigint null references api_links on delete set null deferrable,
    previous_link_id    bigint null references api_links on delete set null deferrable
);

create unique index api_links_params on api_links ( path, md5( params_json ) );



