


ALTER TABLE processed_stories
    ALTER COLUMN stories_id TYPE int;   -- TYPE change - table: processed_stories
                                        -- original:    bigint not null references stories on delete cascade
                                        -- new:         int not null references stories on delete cascade


