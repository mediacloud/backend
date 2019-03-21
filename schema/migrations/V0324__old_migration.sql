

insert into controversy_dates ( controversies_id, start_date, end_date )
    select c.controversies_id, q.start_date, q.end_date
    from controversies c,
        query_story_searches qss, 
        queries q
    where 
        c.query_story_searches_id = qss.query_story_searches_id and
        qss.queries_id = q.queries_id;




