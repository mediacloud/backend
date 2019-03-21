

create index auth_users_email on auth_users( email );
create index auth_users_token on auth_users( api_token );

create table auth_user_ip_tokens (
    auth_user_ip_tokens_id  serial      primary key,
    auth_users_id           int         not null references auth_users on delete cascade,
    api_token               varchar(64) unique not null default generate_api_token() constraint api_token_64_characters check( length( api_token ) = 64 ),
    ip_address              inet    not null
);

create index auth_user_ip_tokens_token on auth_user_ip_tokens ( api_token, ip_address );




