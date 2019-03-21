

create table controversy_query_slices (
    controversy_query_slices_id     serial primary key,
    controversies_id                int not null references controversies on delete cascade,
    name                            varchar ( 1024 ) not null,
    query                           text not null,
    all_time_slices                 boolean not null
);

alter table controversy_dump_time_slices
    add controversy_query_slices_id int null references controversy_query_slices on delete set null;
    
alter table controversy_dump_time_slices add is_shell boolean not null default false;
    



