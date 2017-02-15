--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4606 and 4607.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4606, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4607, import this SQL file:
--
--     psql mediacloud < mediawords-4606-4607.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

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


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4607;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
