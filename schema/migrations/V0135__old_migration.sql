

drop view topic_tweet_full_urls;
create view topic_tweet_full_urls as
    select distinct
            t.topics_id,
            tt.topic_tweets_id, tt.content, tt.publish_date, tt.twitter_user,
            ttd.day, ttd.tweet_count, ttd.num_ch_tweets, ttd.tweets_fetched,
            ttu.url, tsu.stories_id
        from
            topics t
            join topic_tweet_days ttd on ( t.topics_id = ttd.topics_id )
            join topic_tweets tt using ( topic_tweet_days_id )
            join topic_tweet_urls ttu using ( topic_tweets_id )
            left join topic_seed_urls tsu
                on ( tsu.topics_id = t.topics_id and ttu.url = tsu.url );

drop view controversies;
drop view topics_with_user_permission;
drop view topics_with_dates;

alter table topics add twitter_topics_id int null references topics on delete set null;

update topics a set twitter_topics_id = b.topics_id
    from topics b
    where
        a.topics_id = b.twitter_parent_topics_id;

update topics a set ch_monitor_id =  b.ch_monitor_id
    from topics b
    where
        a.twitter_parent_topics_id = b.topics_id;

update topics set ch_monitor_id = null where twitter_topics_id is not null;

alter table topics drop twitter_parent_topics_id;

create view controversies as select topics_id controversies_id, * from topics;

create or replace view topics_with_user_permission as
    with admin_users as (
        select m.auth_users_id
            from auth_roles r
                join auth_users_roles_map m using ( auth_roles_id )
            where
                r.role = 'admin'
    ),

    read_admin_users as (
        select m.auth_users_id
            from auth_roles r
                join auth_users_roles_map m using ( auth_roles_id )
            where
                r.role = 'admin-readonly'
    )

    select
            t.*,
            u.auth_users_id,
            case
                when ( exists ( select 1 from admin_users a where a.auth_users_id = u.auth_users_id ) ) then 'admin'
                when ( tp.permission is not null ) then tp.permission::text
                when ( t.is_public ) then 'read'
                when ( exists ( select 1 from read_admin_users a where a.auth_users_id = u.auth_users_id ) ) then 'read'
                else 'none' end
                as user_permission
        from topics t
            join auth_users u on ( true )
            left join topic_permissions tp using ( topics_id, auth_users_id );


create view topics_with_dates as
    select c.*,
            to_char( td.start_date, 'YYYY-MM-DD' ) start_date,
            to_char( td.end_date, 'YYYY-MM-DD' ) end_date
        from
            topics c
            join topic_dates td on ( c.topics_id = td.topics_id )
        where
            td.boundary;


