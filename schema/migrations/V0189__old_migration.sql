

drop index topic_tweet_urls_tt;
create index topic_tweet_urls_tt on topic_tweet_urls( topic_tweets_id, url );

drop view topics_with_dates;
create view topics_with_dates as
    select c.*,
            to_char( td.start_date, 'YYYY-MM-DD' ) start_date,
            to_char( td.end_date, 'YYYY-MM-DD' ) end_date
        from
            topics c
            join topic_dates td on ( c.topics_id = td.topics_id )
        where
            td.boundary;


drop view topics_with_user_permission;
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




