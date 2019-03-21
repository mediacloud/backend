


-- topics table with auth_users_id and user_permission fields that indicate the permission level for
-- the user for the topic.  permissions in decreasing order are admin, write, read, none.  users with
-- the admin role have admin permission for every topic. users with admin-readonly role have at least
-- read access to every topic.  all users have read access to every is_public topic.  otherwise, the
-- topic_permissions tableis used, with 'none' for no topic_permission.
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




