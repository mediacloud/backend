-- notes for internal media cloud consumption (eg. 'added this for yochai')
alter table media add editor_notes                text null;

-- notes for public consumption (eg. 'leading dissident paper in anatarctica')
alter table media add public_notes                text null;

-- if true, indicates that media cloud closely monitors the health of this source
alter table media add is_monitored                boolean not null default false;

-- if true, users can expect tags and associations in this tag set not to change in major ways
alter table tags add is_static boolean not null default false;

insert into auth_users_roles_map ( auth_users_id, auth_roles_id )
    select auth_users_id, auth_roles_id
        from auth_users u
            join auth_roles r on ( r.role = 'admin-readonly' )
        where
            u.non_public_api and
            not exists (
                select 1
                    from auth_users_roles_map m
                        join auth_roles mr using ( auth_roles_id )
                    where
                        m.auth_users_id = u.auth_users_id and
                        r.role in ( 'admin', 'admin-readonly' )
            );

alter table auth_users drop column non_public_api;


