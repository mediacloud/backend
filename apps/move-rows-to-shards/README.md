# Tables to move

* [ ] **FIXME count how many activities are we going to run**

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
      * [ ] **FIXME skip potential duplicate GUIDs at the start of the production's `stories` table**
    * [x] stories_ap_syndicated
    * [x] story_urls
    * [x] feeds_stories_map_p_\d\d
    * [x] stories_tags_map_p_\d\d
    * [x] story_sentences_p_\d\d
    * [x] solr_import_stories
      * [x] use ON CONFLICT
    * [x] solr_imported_stories
      * [x] use ON CONFLICT
    * [x] processed_stories
      * [x] avoid triggering insert_solr_import_story()
      * [x] use ON CONFLICT
    * [x] topic_merged_stories_map (source_stories_id)
      * [x] use ON CONFLICT
    * [x] story_statistics
    * [x] scraped_stories
    * [x] story_enclosures

* [x] downloads.downloads_id:
    * [x] downloads_error
    * [x] downloads_success_content_\d\d
    * [x] downloads_success_feed_\d\d
    * [x] download_texts_\d\d

* [x] topics.topics_id:
    * [x] topic_stories
      * [x] avoid triggering insert_solr_import_story()
    * [x] topic_links
    * [x] topic_fetch_urls
    * [x] topic_posts
    * [x] topic_post_urls
    * [x] topic_seed_urls
    * [x] snap.stories
      * [x] use ON CONFLICT
    * [x] snap.topic_stories
      * [x] use ON CONFLICT
    * [x] snap.topic_links_cross_media
      * [x] use ON CONFLICT
    * [x] snap.media
      * [x] use ON CONFLICT
    * [x] snap.media_tags_map
      * [x] use ON CONFLICT
    * [x] snap.stories_tags_map
      * [x] use ON CONFLICT
    * [x] snap.story_links
      * [x] use ON CONFLICT
    * [x] snap.story_link_counts
      * [x] use ON CONFLICT
    * [x] snap.medium_link_counts
      * [x] use ON CONFLICT
    * [x] snap.medium_links
      * [x] use ON CONFLICT
    * [x] snap.timespan_posts
    * [x] snap.live_stories
