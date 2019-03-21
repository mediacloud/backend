

drop trigger ss_insert_story_media_stats on story_sentences;
drop trigger ss_update_story_media_stats on story_sentences;
drop trigger story_delete_ss_media_stats on story_sentences;

drop function insert_ss_media_stats();
drop function update_ss_media_stats();
drop function delete_ss_media_stats();



