# Tables to move

* [x] auth_user_request_daily_counts.email:
    * [x] auth_user_request_daily_counts
      * [x] skip (email, day) pairs that already exist in the sharded table

* [x] media.media_id:
    * [x] media_stats
      * [x] skip (media_id, stat_date) pairs that already exist in the sharded table
    * [x] media_coverage_gaps

* [x] stories.stories_id:
    * [x] stories
      * [x] avoid triggering insert_solr_import_story()
    * [x] stories_ap_syndicated
    * [x] story_urls
    * [x] feeds_stories_map
    * [x] stories_tags_map
    * [x] story_sentences
    * [x] solr_import_stories
      * [x] use ON CONFLICT
    * [x] solr_imported_stories
      * [x] use ON CONFLICT
    * [x] topic_merged_stories_map (source_stories_id)
      * [x] use ON CONFLICT
    * [x] story_statistics
    * [x] processed_stories
      * [x] avoid triggering insert_solr_import_story()
      * [x] use ON CONFLICT
    * [x] scraped_stories
    * [x] story_enclosures

* [x] downloads.downloads_id:
    * [x] downloads
    * [x] download_texts

* topics.topics_id:
    * [x] topic_stories
      * [x] avoid triggering insert_solr_import_story()
    * [x] topic_links
    * [x] topic_fetch_urls
    * topic_posts
    * topic_post_urls
    * topic_seed_urls
    * snap.stories
    * snap.topic_stories
    * snap.topic_links_cross_media
    * snap.media
    * snap.media_tags_map
    * snap.stories_tags_map
    * snap.story_links
    * snap.story_link_counts
    * snap.medium_link_counts
    * snap.medium_links
    * snap.timespan_posts
    * snap.live_stories
