

alter table cd.story_link_counts add facebook_share_count int null;

update cd.story_link_counts slc set facebook_share_count = ss.facebook_share_count
    from story_statistics ss where ss.stories_id = slc.stories_id;

drop view controversies_with_dates;
alter table controversies drop column process_with_bitly;
create view controversies_with_dates as
    select c.*,
            to_char( cd.start_date, 'YYYY-MM-DD' ) start_date,
            to_char( cd.end_date, 'YYYY-MM-DD' ) end_date
        from
            controversies c
            join controversy_dates cd on ( c.controversies_id = cd.controversies_id )
        where
            cd.boundary;





