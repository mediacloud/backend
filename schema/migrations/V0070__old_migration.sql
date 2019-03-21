

alter table topics add is_public boolean not null default false;

create type topic_permission AS ENUM ( 'read', 'write', 'admin' );

-- per user permissions for topics
create table topic_permissions (
    topic_permissions_id    serial primary key,
    topics_id               int not null references topics on delete cascade,
    auth_users_id           int not null references auth_users on delete cascade,
    permission              topic_permission not null
);

create index topic_permissions_topic on topic_permissions( topics_id );
create unique index topic_permissions_user on topic_permissions( auth_users_id, topics_id );



