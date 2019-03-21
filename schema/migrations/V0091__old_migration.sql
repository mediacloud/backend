


DROP TABLE IF EXISTS story_sentences_tags_map;

-- Remove orphan tags
-- DELETE FROM tags
-- WHERE NOT EXISTS (SELECT 1 FROM feeds_tags_map WHERE tags.tags_id = feeds_tags_map.tags_id)
--   AND NOT EXISTS (SELECT 1 FROM media_tags_map WHERE tags.tags_id = media_tags_map.tags_id)
--   AND NOT EXISTS (SELECT 1 FROM stories_tags_map WHERE tags.tags_id = stories_tags_map.tags_id)
--   AND NOT EXISTS (SELECT 1 FROM media_suggestions_tags_map WHERE tags.tags_id = media_suggestions_tags_map.tags_id)
-- ;



