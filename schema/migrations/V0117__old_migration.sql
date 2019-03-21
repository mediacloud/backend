

alter table controversy_seed_urls add publish_date text;
alter table controversy_seed_urls add title text;
alter table controversy_seed_urls add guid text;
alter table controversy_seed_urls add content text;
alter table controversies add max_iterations int not null default 15;




