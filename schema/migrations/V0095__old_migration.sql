


begin;

alter table controversy_dump_time_slices add story_count int;
alter table controversy_dump_time_slices add story_link_count int;
alter table controversy_dump_time_slices add medium_count int;
alter table controversy_dump_time_slices add medium_link_count int;

update controversy_dump_time_slices cdts set story_count = q.count
    from ( 
        select count(*) count, c.controversy_dump_time_slices_id
            from cd.story_link_counts c
            group by c.controversy_dump_time_slices_id
    ) q
    where
        q.controversy_dump_time_slices_id = cdts.controversy_dump_time_slices_id;

update controversy_dump_time_slices set story_count = 0 where story_count is null;

update controversy_dump_time_slices cdts set story_link_count = q.count
    from ( 
        select count(*) count, c.controversy_dump_time_slices_id
            from cd.story_links c
            group by c.controversy_dump_time_slices_id
    ) q
    where
        q.controversy_dump_time_slices_id = cdts.controversy_dump_time_slices_id;

update controversy_dump_time_slices set story_link_count = 0 where story_link_count is null;

update controversy_dump_time_slices cdts set medium_count = q.count
    from ( 
        select count(*) count, c.controversy_dump_time_slices_id
            from cd.medium_link_counts c
            group by c.controversy_dump_time_slices_id
    ) q
    where
        q.controversy_dump_time_slices_id = cdts.controversy_dump_time_slices_id;

update controversy_dump_time_slices set medium_count = 0 where medium_count is null;

update controversy_dump_time_slices cdts set medium_link_count = q.count
    from ( 
        select count(*) count, c.controversy_dump_time_slices_id
            from cd.medium_links c
            group by c.controversy_dump_time_slices_id
    ) q
    where
        q.controversy_dump_time_slices_id = cdts.controversy_dump_time_slices_id;

update controversy_dump_time_slices set medium_link_count = 0 where medium_link_count is null;

alter table controversy_dump_time_slices alter story_count set not null;
alter table controversy_dump_time_slices alter story_link_count set not null;
alter table controversy_dump_time_slices alter medium_count set not null;
alter table controversy_dump_time_slices alter medium_link_count set not null;

commit; 

