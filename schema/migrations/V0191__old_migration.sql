

ALTER TABLE controversies
	ALTER COLUMN query_story_searches_id TYPE int not null references query_story_searches /* TYPE change - table: controversies original: int new: int not null references query_story_searches */,
	ALTER COLUMN query_story_searches_id DROP NOT NULL;

ALTER TABLE controversy_seed_urls
	ADD COLUMN assume_match boolean not null DEFAULT false;
	
CREATE INDEX controversy_seed_urls_url ON controversy_seed_urls (url);


