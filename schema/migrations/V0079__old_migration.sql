
create index controversy_merged_stories_map_story on controversy_merged_stories_map ( target_stories_id );
create index controversy_links_ref_story on controversy_links ( ref_stories_id );
create index controversy_seed_urls_story on controversy_seed_urls ( stories_id );
create index authors_stories_queue_story on authors_stories_queue( stories_id );
create index story_subsets_processed_stories_map_processed_stories_id on story_subsets_processed_stories_map ( processed_stories_id );



