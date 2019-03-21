

alter table media_tags_map add tagged_date date null;
alter table media_tags_map alter tagged_date set default now();



