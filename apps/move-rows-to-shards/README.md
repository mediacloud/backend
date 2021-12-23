# Tables to move

* [ ] **FIXME increase shard count**
* [ ] **FIXME skip potential duplicate GUIDs at the start of the production's `stories` table**

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


# Tables to convert to UNION

* [ ] `sub _fetch_list`

* [ ] auth_user_request_daily_counts.email:
    * [ ] auth_user_request_daily_counts

* [ ] media.media_id:
    * [ ] media_stats
    * [ ] media_coverage_gaps

* [ ] stories.stories_id:
    * [x] stories
    * [x] stories_ap_syndicated
    * [x] story_urls
    * [x] feeds_stories_map_p_\d\d
    * [ ] stories_tags_map_p_\d\d
    * [ ] story_sentences_p_\d\d
    * [ ] solr_import_stories
    * [ ] solr_imported_stories
    * [ ] processed_stories
    * [ ] topic_merged_stories_map (source_stories_id)
    * [ ] story_statistics
    * [ ] scraped_stories
    * [ ] story_enclosures

* [ ] downloads.downloads_id:
    * [ ] downloads_error
    * [ ] downloads_success_content_\d\d
    * [ ] downloads_success_feed_\d\d
    * [ ] download_texts_\d\d

* [ ] topics.topics_id:
    * [ ] topic_stories
    * [ ] topic_links
    * [ ] topic_fetch_urls
    * [ ] topic_posts
    * [ ] topic_post_urls
    * [ ] topic_seed_urls
    * [ ] snap.stories
    * [ ] snap.topic_stories
    * [ ] snap.topic_links_cross_media
    * [ ] snap.media
    * [ ] snap.media_tags_map
    * [ ] snap.stories_tags_map
    * [ ] snap.story_links
    * [ ] snap.story_link_counts
    * [ ] snap.medium_link_counts
    * [ ] snap.medium_links
    * [ ] snap.timespan_posts
    * [ ] snap.live_stories
