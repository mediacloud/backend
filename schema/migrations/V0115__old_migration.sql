


begin;

create table cdts_files (
    cdts_files_id                   serial primary key,
    controversy_dump_time_slices_id int not null references controversy_dump_time_slices on delete cascade,
    file_name                       text,
    file_content                    text
);

create index cdts_files_cdts on cdts_files ( controversy_dump_time_slices_id );

create table cd_files (
    cd_files_id                     serial primary key,
    controversy_dumps_id            int not null references controversy_dumps on delete cascade,
    file_name                       text,
    file_content                    text
);

create index cd_files_cd on cd_files ( controversy_dumps_id );

insert into cdts_files
    ( controversy_dump_time_slices_id, file_name, file_content )
    select controversy_dump_time_slices_id, 'stories.csv', stories_csv
        from controversy_dump_time_slices;

insert into cdts_files
    ( controversy_dump_time_slices_id, file_name, file_content )
    select controversy_dump_time_slices_id, 'story_links.csv', story_links_csv
        from controversy_dump_time_slices;

insert into cdts_files
    ( controversy_dump_time_slices_id, file_name, file_content )
    select controversy_dump_time_slices_id, 'media.csv', media_csv
        from controversy_dump_time_slices;

insert into cdts_files
    ( controversy_dump_time_slices_id, file_name, file_content )
    select controversy_dump_time_slices_id, 'medium_links.csv', medium_links_csv
        from controversy_dump_time_slices;

insert into cdts_files
    ( controversy_dump_time_slices_id, file_name, file_content )
    select controversy_dump_time_slices_id, 'media.gexf', gexf
        from controversy_dump_time_slices;

insert into cd_files
    ( controversy_dumps_id, file_name, file_content )
    select controversy_dumps_id, 'daily_counts.csv', daily_counts_csv
        from controversy_dumps;

insert into cd_files
    ( controversy_dumps_id, file_name, file_content )
    select controversy_dumps_id, 'weekly_counts.csv', weekly_counts_csv
        from controversy_dumps;

alter table controversy_dump_time_slices drop stories_csv;
alter table controversy_dump_time_slices drop story_links_csv;
alter table controversy_dump_time_slices drop media_csv;
alter table controversy_dump_time_slices drop medium_links_csv;
alter table controversy_dump_time_slices drop gexf;

alter table controversy_dumps drop daily_counts_csv;
alter table controversy_dumps drop weekly_counts_csv;

commit; 

