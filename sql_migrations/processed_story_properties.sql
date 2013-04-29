
CREATE TABLE processed_stories_properties (
  processed_stories_properties_id bigserial primary key,
  stories_id bigint NOT NULL references story_subsets on delete cascade,
  processed_stories_id bigint NOT NULL references processed_stories on delete cascade,
  properties hstore NOT NULL
);

CREATE INDEX processed_stories_properties_properties ON processed_stories_properties USING GIN( properties );
CREATE UNIQUE INDEX processed_stories_properties_stories_id_processed_stories_id ON processed_stories_properties( stories_id, processed_stories_id );
CREATE UNIQUE INDEX processed_stories_properties_stories_id ON processed_stories_properties( stories_id );
CREATE UNIQUE INDEX processed_stories_properties_processed_stories_id ON processed_stories_properties( processed_stories_id );

