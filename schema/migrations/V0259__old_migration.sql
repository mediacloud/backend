

drop view topics_with_user_permission;
drop view controversies;

alter table topics drop column if exists topic_tag_sets_id;
alter table topics drop has_been_spidered;
alter table topics drop has_been_dumped;
alter table topics rename error_message to message;

update topics set state = 'queued' where state = 'created but not queued';
update topics set state = 'completed' where state = 'ready';
update topics set state = 'running', message = state where length( state ) > 25;

alter table snapshots rename error_message to message;

update snapshots set state = 'error' where state like '%failed';
update snapshots set state = 'error', message = state where state <> 'completed';

drop trigger topic_tag_set on topics;
drop function insert_topic_tag_set();

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




