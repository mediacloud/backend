

CREATE TABLE raw_downloads (
	raw_downloads_id   SERIAL  PRIMARY KEY,
	downloads_id       INTEGER NOT NULL REFERENCES downloads ON DELETE CASCADE,
	raw_data           BYTEA   NOT NULL         
);
CREATE UNIQUE INDEX raw_downloads_downloads_id ON raw_downloads (downloads_id);




