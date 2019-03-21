

-- job states as implemented in MediaWords::AbstractJob
create table job_states (
    job_states_id           serial primary key,

    --MediaWords::Job::* class implementing the job
    class                   varchar( 1024 ) not null,

    -- short class specific state
    state                   varchar( 1024 ) not null,

    -- optional longer message describing the state, such as a stack trace for an error
    message                 text,

    -- last time this job state was updated
    last_updated            timestamp not null default now(),

    -- details about the job
    args                    json not null,
    priority                text not  null,

    -- the hostname and process_id of the running process
    hostname                text not null,
    process_id              int not null
);

create index job_states_class_date on job_states( class, last_updated );



