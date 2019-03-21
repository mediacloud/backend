

alter index snap.story_link_counts_story rename to story_link_counts_ts;
create index story_link_counts_story on snap.story_link_counts( stories_id );

alter table snapshots add searchable boolean not null default false;

update snapshots set searchable = true;

create index snapshots_searchable on snapshots ( searchable );



