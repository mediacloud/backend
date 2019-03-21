

create table auth_registration_queue (
    auth_registration_queue_id  serial  primary key,
    name                        text    not null,
    email                       text    not null,
    organization                text    not null,
    motivation                  text    not null,
    approved                    boolean default false
);





