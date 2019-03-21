

alter table controversies add has_been_spidered boolean not null default false;
alter table controversies add has_been_dumped boolean not null default false;

alter table controversies add state text not null default 'created but not queued';
alter table controversies add error_message text null;

alter table controversy_dumps add state text not null default 'queued';
alter table controversy_dumps add error_message text null;

update controversies c set has_been_spidered = true where not exists (
    select 1 from controversy_stories cs
        where iteration < 15 and link_mined = false and c.controversies_id = cs.controversies_id
);

update controversies set state = 'spidering completed' where has_been_spidered;
update controversies set state = 'unknown' where state != 'spidering completed';

update controversy_dumps set state = 'completed' where exists (
    select 1 from controversy_dump_time_slices cdts
        where cdts.controversy_dumps_id = cdts.controversy_dumps_id and cdts.period = 'overall'
);

update controversies c set has_been_dumped = true where exists (
    select 1 from controversy_dumps cd where c.controversies_id = cd.controversies_id and cd.state = 'completed'
);

drop view controversies_with_dates;
create view controversies_with_dates as
    select c.*,
            to_char( cd.start_date, 'YYYY-MM-DD' ) start_date,
            to_char( cd.end_date, 'YYYY-MM-DD' ) end_date
        from
            controversies c
            join controversy_dates cd on ( c.controversies_id = cd.controversies_id )
        where
            cd.boundary;



