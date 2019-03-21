
create type topics_job_queue_type AS ENUM ( 'mc', 'public' );

alter table topics add job_queue topics_job_queue_type;
update topics set job_queue = 'mc';
alter table topics alter job_queue set not null;

alter table topics add max_stories int null;

create temporary table topic_num_stories as
     select t.topics_id, max( ts.story_count ) num_stories
        from topics t
            join snapshots s using ( topics_id )
            join timespans ts using ( snapshots_id )
        group by t.topics_id;

update topics set max_stories = 200000;
update topics t set max_stories = tns.num_stories * 2
    from topic_num_stories tns
    where
        t.topics_id = tns.topics_id and
        tns.num_stories > 100000;

alter table topics alter max_stories set not null;

alter table topics add max_stories_reached boolean not null default false;

alter table auth_users add max_topic_stories int not null default 100000;



