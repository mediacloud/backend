

create view controversies as select topics_id controversies_id, * from topics;
create view controversy_dumps as
    select snapshots_id controversy_dumps_id, topics_id controversies_id, snapshot_date dump_date, * from snapshots;
create view controversy_dump_time_slices as
    select timespans_id controversy_dump_time_slices_id, snapshots_id controversy_dumps_id, foci_id controversy_query_slices_id, *
        from timespans;



