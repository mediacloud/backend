

-- keep track of per domain web requests so that we can throttle them using mediawords.util.web.user_agent.throttled.
-- this is unlogged because we don't care about anything more than about 10 seconds old.  we don't have a primary
-- key because we want it just to be a fast table for temporary storage.
create unlogged table domain_web_requests (
    domain          text not null,
    request_time    timestamp not null default now()
);

create index domain_web_requests_domain on domain_web_requests ( domain );

-- return false if there is a request for the given domain within the last domain_timeout_arg seconds.  otherwise
-- return true and insert a row into domain_web_request for the domain.  this function does not lock the table and
-- so may allow some parallel requests through.
create or replace function get_domain_web_requests_lock( domain_arg text, domain_timeout_arg int ) returns boolean as $$
begin

-- we don't want this table to grow forever or to have to manage it externally, so just truncate about every
-- 1 million requests.  only do this if there are more than 1000 rows in the table so that unit tests will not
-- randomly fail.
if ( select random() * 1000000 ) <  1 then
    if exists ( select 1 from domain_web_requests offset 1000 ) then
        truncate table domain_web_requests;
    end if;
end if;

if exists (
    select *
        from domain_web_requests
        where
            domain = domain_arg and
            extract( epoch from now() - request_time ) < domain_timeout_arg
    ) then

    return false;
end if;

delete from domain_web_requests where domain = domain_arg;
insert into domain_web_requests (domain) select domain_arg;

return true;
end
$$ language plpgsql;



