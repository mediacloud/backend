


DELETE FROM auth_roles
WHERE role = 'search';


DELETE FROM activities
WHERE name IN (
	'tm_remove_story_from_topic',
	'tm_media_merge',
	'tm_story_merge',
	'tm_search_tag_run',
	'tm_search_tag_change',
	'story_edit',
	'media_edit'
);




