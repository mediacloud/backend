

alter table topics add is_story_index_ready boolean not null default true;
update topics set is_story_index_ready = false;




