

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




