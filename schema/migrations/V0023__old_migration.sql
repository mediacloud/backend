


CREATE INDEX media_name_trgm ON media USING gin (name gin_trgm_ops);

CREATE INDEX media_url_trgm ON media USING gin (url gin_trgm_ops);

CREATE INDEX dashboards_name_trgm ON dashboards USING gin (name gin_trgm_ops);

CREATE INDEX media_sets_name_trgm ON media_sets USING gin (name gin_trgm_ops);

CREATE INDEX media_sets_description_trgm ON media_sets USING gin (description gin_trgm_ops);

