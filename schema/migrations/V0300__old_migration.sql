
create index stories_publish_day on stories ( date_trunc( 'day', publish_date ) );
    
create index downloads_feed_download_time on downloads ( feeds_id, download_time );




