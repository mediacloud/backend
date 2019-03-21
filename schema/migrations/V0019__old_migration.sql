


ALTER TABLE solr_import_stories
    RENAME TO solr_import_extra_stories;

ALTER INDEX solr_import_stories_story
    RENAME TO solr_import_extra_stories_story;

INSERT INTO solr_import_extra_stories (stories_id)
    SELECT stories_id
    FROM bitly_clicks_total;




