


ALTER TABLE media
    ADD COLUMN annotate_with_corenlp BOOLEAN	NOT NULL DEFAULT(false);

ALTER TABLE dashboards
	ADD COLUMN public	BOOLEAN	NOT NULL DEFAULT(true);



