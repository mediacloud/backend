


CREATE UNIQUE INDEX downloads_for_extractor_trainer ON downloads ( downloads_id, feeds_id) where file_status <> 'missing' and type = 'content' and state = 'success';

