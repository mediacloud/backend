create table processed_stories (
    processed_stories_id        bigserial          primary key,
    stories_id                  bigint             not null references stories on delete cascade
);


INSERT INTO processed_stories ( stories_id ) select distinct(stories_id) from story_sentences ;

