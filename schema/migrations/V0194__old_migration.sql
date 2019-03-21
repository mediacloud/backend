


DROP TRIGGER IF EXISTS ss_insert_story_media_stats ON story_sentences_nonpartitioned;
DROP TRIGGER IF EXISTS ss_update_story_media_stats ON story_sentences_nonpartitioned;
DROP TRIGGER IF EXISTS story_delete_ss_media_stats ON story_sentences_nonpartitioned;

DROP FUNCTION IF EXISTS insert_ss_media_stats();
DROP FUNCTION IF EXISTS update_ss_media_stats();
DROP FUNCTION IF EXISTS delete_ss_media_stats();



