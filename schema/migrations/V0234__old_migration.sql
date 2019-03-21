

CREATE TABLE processed_stories (
	processed_stories_id bigserial          primary key,
	stories_id bigint             not null references stories on delete cascade
);


