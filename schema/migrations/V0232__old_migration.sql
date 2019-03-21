

CREATE TABLE story_subsets (
	story_subsets_id bigserial          primary key,
	start_date timestamp with time zone,
	end_date timestamp with time zone,
	media_id int references media_sets,
	media_sets_id int references media_sets,
	ready boolean DEFAULT 'false',
	last_processed_stories_id bigint references processed_stories(processed_stories_id)
);

CREATE TABLE story_subsets_processed_stories_map (
	story_subsets_processed_stories_map_id bigserial primary key,
	story_subsets_id bigint NOT NULL references story_subsets on delete cascade,
	processed_stories_id bigint NOT NULL references processed_stories on delete cascade
);


